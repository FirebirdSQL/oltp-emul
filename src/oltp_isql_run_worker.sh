#!/bin/bash

function pause(){
   read -p "$*"
}

msg_noarg() {
  clear
  echo Current script:
  echo $shname | sed -e 's/^/    /'
  echo
  echo - must be called from:
  echo $shdir/1run_oltp_emul.sh | sed -e 's/^/    /'
  echo
  echo Do not run it yourself.
  echo
  pause "Press any key to exit. . ."
}

sho() {
  local msg=$1
  local log=$2
  local use_ms=${3:-0}
  local dts
  if [[ $use_ms -eq 0 ]]; then
     dts=$(date +'%d.%m.%y %H:%M:%S')
  else
     dts=$(date +'%d.%m.%y %H:%M:%S.%3N')
  fi
  echo $dts. $msg
  echo $dts. $msg>>$log
}

apply_cmd() {
  local run_cmd=$1
  local line_prefix=$2
  local log_file=$3
  local zap_log=${4:-0}
  local tmp_log
  if [ $zap_log -eq 1 ]; then
      rm -f $log_file
  fi
  tmp_log=${log_file%.*}.$(date +'%y%m%d_%H%M%S').tmp
  sho "Command: $run_cmd" $log_file
  eval $run_cmd 1>$tmp_log 2>&1
  # NB: output of some commands (e.g. 'fdisk -l') may contain asterisk:
  # Disk /dev/sda: 599.9 GB, 599932581888 bytes, 1171743324 sectors
  # Units = sectors of 1 * 512 = 512 bytes
  # Sector size (logical/physical): 512 bytes / 512 bytes
  # If line with '*' will be echoed then all files from current folder will be substituted instead of this '*'.
  # In order to avoid this one need to enclose into double quotes name of such variable, i.e.: "$line" but not $line 
  # See: https://stackoverflow.com/questions/102049/how-do-i-escape-the-wildcard-asterisk-character-in-bash
  while read line; do
    echo ${line_prefix}: "$line"
    echo ${line_prefix}: "$line" | sed -e 's/^/    /' >> $log_file
  done < <( cat $tmp_log )
  rm -f $tmp_log
  echo >> $log_file
}


catch_err() {
  local retcode=$1
  local log4all=$2
  local tmperr=$3
  local addnfo=${4:-""}
  local quit_if_error=${5:-1}
  if [[ $retcode -eq 0 ]]; then
      if [[ -s $tmperr ]]; then
          echo
          sho "Error log $tmperr is NOT EMPTY." $log4all
          echo ...............................
          cat $tmperr | sed -e 's/^/    /'
          cat $tmperr | sed -e 's/^/    /' >>$log4all
          echo ...............................
          if [[ ! -z "$addnfo" ]]; then
              echo
              echo Additional info / advice:
              echo $addnfo
              echo $addnfo >>$log4all
              echo
          fi

          if [[ $quit_if_error -eq 1 ]]; then
              sho "Script is terminated." $log4all
              exit 1
          fi
      else
          sho "Result: SUCCESS." $log4all
          rm -f $tmperr
      fi
  else
      sho "Retcode=$retcode. Check $tmperr:" $log4all
      cat $tmperr | sed -e 's/^/    /'
      cat $tmperr | sed -e 's/^/    /' >>$log4all
      sho "Job terminated."  $log4all
      exit 1
  fi
}

log_elapsed_time() {
    local s1=$1

    # name of either "main" (text) LOG or HTML report:
    local report_file=$2
    local what_was_done=${3:-""}
    local s2=$(date +%s)
    local sd=$(date -u -d "0 $s2 sec - $s1 sec" +"%H:%M:%S")
    local elapsed_time_msg="Done for $sd, from $(date -d @$s1 +'%d-%m-%Y %H:%M:%S') to $(date -d @$s2 +'%d-%m-%Y %H:%M:%S')."
    if [[ ! -z "${what_was_done}" ]]; then
        elapsed_time_msg="Completed \"$what_was_done\". $elapsed_time_msg"
    fi
    if [[ "${report_file##*.}" == *"htm"* ]]; then
        echo "<br>$elapsed_time_msg" >>$report_file
    else
        sho "$elapsed_time_msg" $report_file
    fi
}


get_diff_fblog() {
    local mode=$1
    local fb_major=$2
    local sid=$3
    local fblog_beg=$4
    local log4sid=$5
    local  __resultvar=$6

    sho "Routine $FUNCNAME: start." $log4sid

    local get_log_switch
    local fb_home_dir
    local abend_flag=0
    local tmpdiff=$tmpdir/tmp_fb_diff.$sid.tmp
    local tmp_sql=$tmpdir/tmp_g_stop.$sid.tmp
    local fb_log_end=$tmpdir/tmp_fb_end.$sid.tmp

    [[ $fb_major -eq 25 ]] && get_log_switch=action_get_ib_log || get_log_switch=action_get_fb_log
    local run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth $get_log_switch"

    # fbc, host,port, dbconn, dbauth -- must be known here
    rm -f $tmpdir/tmp_fb_diff.$sid.tmp
    
    sho "SID=$sid. Gathering firebird.log, mode=$mode" $log4sid

    # fblog_beg = $tmpdir/fb_log_when_test_started.$fb.log
    if [[ $dbconn =~ .*localhost[/:]{1}.* || $dbconn =~ .*127.0.0.1[/:]{1}.* ]]; then
        fb_home_dir="$(dirname "$fbc")"
        sho "SID=$sid. ISQL session is running on server-side, we can open $fb_home_dir/firebird.log directly call fbsvcmgr to get its content." $log4sid
        echo -e 'Command: diff --unchanged-line-format="" --new-line-format=":%dn: %L" $fblog_beg $fb_home_dir/firebird.log' >> $log4sid
	echo --- start of diff output --- >>$tmpdiff
	diff --unchanged-line-format="" --new-line-format=":%dn: %L" $fblog_beg $fb_home_dir/firebird.log 1>>$tmpdiff 2>&1
	echo --- start of diff output --- >>$tmpdiff
    else
        sho "SID=$sid. Use command $run_fbs to get content of firebird.log" $log4sid
        $run_fbs 1>$fblog_end 2>>$log4sid
        sho "SID=$sid. Done, size of $fblog_end: $(stat -c%s $fblog_end). Starting comparison of old and new firebird log" $log4sid
	cat <<-EOF >$tmpdiff
		--- start of diff output ---
		diff --unchanged-line-format="" --new-line-format=":%dn: %L"  $fblog_beg $fblog_end
		--- end of diff output ---
	EOF
    fi
    cat $tmpdiff
    cat $tmpdiff >> $log4sid

    if  [ "$mode" == "check_for_crash" ] ; then
        if grep -q -i -E "(/firebird|/fb_smp_server).*terminated.*abnormally" $tmpdiff; then
            sho "SID=$sid. At least one message about FB crash detected in the diff file of firebird.log" $log4sid
            sho "SID=$sid. Test must be prematurely terminated. Trying to change sequence g_stop_test to negative value." $log4sid
            ###########################################################################################################
            ###   F O R C E D L Y     T E R M I N A T E     B E C A U S E     O F     F I R E B I R D    C R A S H  ###
            ###########################################################################################################
		cat <<-EOF >$tmp_sql
		set list on;
		set echo on;
		set bail on;
		-- ::: NOTE::: Command 'show sequence <g>' actually does:
		-- select gen_id(<G>,0) from rdb$database, i.e. it queries database table.
		-- It can take valuable time in case of extremely high workload (1500+ attachments).
		-- We can avoid such query this by using execute block
		set term ^;
		execute block returns( dts_before_change_gen timestamp, g_stop_current bigint, dts_after_change_gen timestamp, g_stop_changed bigint ) as
		    declare v_dummy bigint;
		begin
		    dts_before_change_gen = 'now';
		    g_stop_current = gen_id( g_stop_test, 0 );
		    if ( g_stop_current < 0 ) then
		    begin
		       suspend;
		       -- value of stop-flag sequence already was changed to negative by another session.
		       -- no need to change it here, just raise exception in order to break from this .sql:
		       exception ex_test_cancellation;
		    end

		    -- 14.09.2020: use this instead of alter sequence restart with ...
		    -- because it can raise SQLSTATE = 40001 / -deadlock /-update conflicts!
		    g_stop_changed = gen_id( g_stop_test, -abs(gen_id(g_stop_test,0))-9999999 );
		    dts_after_change_gen = 'now';
		    suspend;
		end^
		set term ;^
		exit;
		EOF
	    $isql_name $dbconn $dbauth -q -n -nod -i $tmp_sql 1>>$log4sid 2>&1
            sho "SID=$sid. Done. All workers soon will stop their job." $log4sid
            rm -f $tmp_sql

            abend_flag=1

        fi
    fi
    rm -f $tmpdiff
    rm -f $fb_log_end

    sho "Routine $FUNCNAME: finish." $log4sid
    if [[ $abend_flag -eq 1 ]]; then
        if [[ $sid -eq 1 ]]; then
            sho "SID=1: crash detected but script will continue to make final report." $log4sid
        else
            sho "SID=$sid. Script terminated because of detected FB crash." $log4sid
            rm -f $sid_starter_sql
            exit 1
        fi
    fi
    # this will be be used in caller as return value:
    eval $__resultvar="$abend_flag"
}
# get_diff_fblog

# -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

get_sqlda_fld_name() {
    local fb=$1
    local sqlda_name=$2
    local fld_name=UNKNOWN

    # Extract LAST word from SQLDA field alias. Has sense only in FB 2.5 because of parenthesis. Example:
    # select rdb$description as rdb_desc, rdb$relation_id rel_id, rdb$security_class sec_class, rdb$character_set_name cset_name from rdb$database;
    # Firebird 2.5:
    #  :  name: (15)RDB$DESCRIPTION  alias: (8)RDB_DESC
    #  :  name: (15)RDB$RELATION_ID  alias: (6)REL_ID
    #  :  name: (18)RDB$SECURITY_CLASS  alias: (9)SEC_CLASS
    #  :  name: (22)RDB$CHARACTER_SET_NAME  alias: (9)CSET_NAME
    # Firebird 3.0:
    #  :  name: RDB$DESCRIPTION  alias: RDB_DESC
    #  :  name: RDB$RELATION_ID  alias: REL_ID
    #  :  name: RDB$SECURITY_CLASS  alias: SEC_CLASS
    #  :  name: RDB$CHARACTER_SET_NAME  alias: CSET_NAME

    if [ "$fb"=="25" ]; then
       # Example: $(echo "(8)   CATEGORY" | awk -F[" ()"] '{print $NF}') --> 'CATEGORY' (get last token)
       eval $fld_name="$(echo $sqlda_name  | awk -F[' ()'] '{print $NF}')"
    else
       eval $result=$fldname
    fi
}

# -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

add_html_text() {
    local src_file=$1
    local htm_file=$2
    local add_br=${3:-1}
    local line_prefix=$4
    local use_style=$5
    if [[ "$line_prefix" == "null" ]]; then
        unset line_prefix
    fi

    if [[  ! -z "$use_style" ]]; then
        if [[ "$use_style" == "pre" ]]; then
            # This is used when data of 'gstat -r' are written to html:
            echo "<pre>" >>$htm_file
        else
            echo "<div class=\"$use_style\">" >>$htm_file
        fi
    fi

    #grep . ./foo.txt |\
    #while read data; do
    #    echo "$data"
    #done

    # ::: NOTE :::
    # We have to read text file and bring its line to html WITHOUT any distortion.
    # This:
    #    while read row_x; do
    #        . . .
    #    done < <( grep . $src_file )
    # -- removes leading spaces in input lines, not good for e.g. gstat output.
    # Following will read every line and replace TAB with four spaces.
    # No other changes will be made in the source line:
    #
    local IFS=''
    cat $src_file | sed 's/\t/    /g' | \
    while read row_x; do
        line=${line_prefix}"${row_x}"
        #echo QQQlineQQQ "$line"
        if [[ "$line" == *"\$css\$error\$"* ]]; then
            ccss="${line/\$css\$error\$/}"
            line="<span class=\"error\">$ccss</span>"
        elif [[ "$line" == *"\$css\$fault\$"* ]]; then
            ccss="${line/\$css\$fault\$/}"
            line="<span class=\"fault\">$ccss</span>"
        elif [[ "$line" == *"\$css\$warning\$"* ]]; then
            ccss="${line/\$css\$warning\$/}"
            line="<span class=\"warning\">$ccss</span>"
        elif [[ "$line" == *"\$css\$success\$"* ]]; then
            ccss="${line/\$css\$success\$/}"
            line="<span class=\"success\">$ccss</span>"
        fi
        if [[ $add_br -eq 1 ]]; then
            echo "${line}<br>" >>$htm_file
        else
            echo "${line}" >>$htm_file
        fi
    done

    if [[  ! -z "$use_style" ]]; then
        if [[ "$use_style" == "pre" ]]; then
            echo "</pre>" >>$htm_file
        else
            echo "</div>" >>$htm_file
        fi
    fi

}
# end of: add_html_text()
# -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

add_html_table() {
    local sql_in=$1
    local htm_file=$2
    
    # 04.05.2020: file with key-value pairs: name of fields in $sql_in for drawing in X- and Y-axis, etc
    local chart_settings_file=$3

    local msg
    local sql_temp=$tmpdir/make_html_table.tmp.sql
    local sql_log=$tmpdir/make_html_table.tmp.log
    local sql_err=$tmpdir/make_html_table.tmp.err
    local tmp_sqlda=$tmpdir/make_html_table.tmp.sqd
    local tmp_nums=$tmpdir/make_html_table.tmp.num
    local tmp_html=$tmpdir/make_html_table.tmp.html
    local tmp_chart_data=$tmpdir/make_html_chart_data.tmp
    local tmp_chart_html=$tmpdir/make_html_chart_data.html

    local tho thc tro trc tdo tdc tdno tdnc

    local num_list col_indx col_type fld_name
    local x_axis_field
    local y_axis_field
    local draw_func_name
    local chart_title
    local href_name
    local href_title
    local x_axis_title
    local y_axis_title
    local chart_color
    local axis_color
    local x_axis_slanted_labels
    local x_values_skip_list
    local chart_type
    local point_size
    
    # 15.05.2020: draw only chart, without table.
    local chart_only_show
    # add 'display: inline-block;' to DIV in order to show it in ONE LINE after previous div (if it is possible).
    # Example: http://interestingwebs.blogspot.com/2012/10/div-side-by-side-in-one-line.html
    local chart_inline_block
    local div_inline_expr
    
    # chart_libs_reload -- whether we have to load basic google charts libraries HERE rather than suppose
    # they are loaded in the whole web page <head> section (i.e. in ONE place, ONE time for the page) ?
    # https://developers.google.com/chart/interactive/docs/basic_load_libs
    # default 0; if 1 then initializing of google chart will be HERE
    # ::: NB ::: Passing 1 here NOT recommended! runtime error can occur after drawing 6-7 charts in one page:
    # too much recursion (Firefox) or "Maximum Call Stack Size Exceeded" (Chrome).
    # See discussion here: https://groups.google.com/forum/#!topic/Google-Visualization-Api/iigCT7a-MFk
    local chart_libs_reload
    
    # 16.05.2020
    local y_format_list

    rm -f $tmp_html $tmp_chart_data $tmp_chart_html

    if [[ -f ${chart_settings_file} ]]; then

        # y_fields_list=metadata cache memo used;memo used by attachments;memo used by transactions;memo used by statements
        # y_colors_list=DarkCyan;                Red;                     Green;                    Brown
        # y_legends_list=memory for metadata; memory for attachments; memory for transactions; memory for statements
        # y_list_delimiter=;

        draw_func_name=$(grep -i draw_func_name $chart_settings_file | awk -F '=' '{print $2}')
        x_axis_field=$(grep -i x_axis_field $chart_settings_file | awk -F '=' '{print $2}')
        x_axis_title=$(grep -i x_axis_title $chart_settings_file | awk -F '=' '{print $2}')

        y_fields_list=$(grep -i y_fields_list $chart_settings_file | awk -F '=' '{print $2}' | sed 's/ *$//g')

        # Remove last character from list of columns to be shown if it is ';':
        if [[ "${y_fields_list:(-1)}" == ";" ]]; then
            y_fields_list=${y_fields_list::-1}
        fi

        # https://developers.google.com/chart/interactive/docs/reference#numberformatter
        # List of formats (optional but all columns must be involved if specified):
        # pattern: '0';   pattern: '0.00',negativeColor: 'red';   fractionDigits: 4;   etc
        y_format_list=$(grep -i y_format_list $chart_settings_file | awk -F '=' '{print $2}' | sed 's/ *$//g')

        # Optional: 'log' --> show char with logarithmic scale in Y-axis:
        y_scale_type=$(grep -i y_scale_type $chart_settings_file | awk -F '=' '{print $2}')

        if [[ -z "${y_fields_list}" ]]; then
        
            # OLD, DO NOT USE! REMOVE LATER!
            #################################
            
            y_axis_field=$(grep -i y_axis_field $chart_settings_file | awk -F '=' '{print $2}')
            y_axis_title=$(grep -i y_axis_title $chart_settings_file | awk -F '=' '{print $2}')
            chart_color=$(grep -i chart_color $chart_settings_file | awk -F '=' '{print $2}')
            [[ -z "$chart_color" ]] && chart_color=DarkSeaGreen

            cols_for_data=",${y_axis_field},"
            # what will be written into 'options' section as chart color definition:
            color_expr="colors: ['$chart_color']"

            # first element for arrayToDataTable() is list of legends which are displayed.
            # If no legends must be show then this element looks like [ '', '' ]
            # but it MUST present in data anyway:
            if [[ -z "${y_legends_list}" ]]; then
                legend_expr="[ '', '${y_axis_field}']"
            else
                legend_expr="[ '', '${y_legends_list}']"
            fi

            legpos_expr="legend:{position:'none'}"

        else
            y_legends_list=$(grep -i y_legends_list $chart_settings_file | awk -F '=' '{print $2}')
            y_leg_maxlines=$(grep -i y_leg_maxlines $chart_settings_file | awk -F '=' '{print $2}')
            [[ -z "$y_leg_maxlines" ]] && y_leg_maxlines=3

            y_colors_list=$(grep -i y_colors_list $chart_settings_file | awk -F '=' '{print $2}')
            y_list_delimiter=$(grep -i y_list_delimiter $chart_settings_file | awk -F '=' '{print $2}')
            [[ -z "$y_list_delimiter" ]] && y_list_delimiter=";"

            y_charts_count=$(echo $y_fields_list | awk -F ';' '{print NF}')

            cols_for_data=","
            while read token; do
                cols_for_data=${cols_for_data}"'${token}',"
            done < <( echo ${y_fields_list} | awk -F';' '{for (i=1;i<=NF;i++) print $i}' ) # do NOT use -F'${y_list_delimiter}' here! IT DOES NOT WORK!
            # Result: cols_for_data="[,'metadata cache memo used','memo used by attachments','memo used by transactions','memo used by statements',]" -- no leading and trailing spaces

            color_expr="colors: ["
            while read token; do
                color_expr=${color_expr}"'${token}',"
            done < <( echo ${y_colors_list} | awk -F';' '{for (i=1;i<=NF;i++) print $i}' ) # do NOT use -F'${y_list_delimiter}' here! IT DOES NOT WORK!
            color_expr=${color_expr}"]"
            # Result: color_expr=colors: ['DarkCyan','Red','Green','Brown',],

            if [[ -z "${y_legends_list}" ]]; then
                legend_expr="[ '',"
                while read token; do
                    legend_expr=${legend_expr}"'${token}',"
                done < <( echo ${y_fields_list} | awk -F';' '{for (i=1;i<=NF;i++) print $i}' ) # do NOT use -F'${y_legend_delimiter}' here! IT DOES NOT WORK!
            else
                legend_expr="[ '',"
                while read token; do
                    legend_expr=${legend_expr}"'${token}',"
                done < <( echo ${y_legends_list} | awk -F';' '{for (i=1;i<=NF;i++) print $i}' ) # do NOT use -F'${y_legend_delimiter}' here! IT DOES NOT WORK!
            fi
            legend_expr=${legend_expr}"]"
            legpos_expr="legend:{ position:'top', maxLines: $y_leg_maxlines }"
            # Result legend_expr=[ '','memory for metadata','memory for attachments','memory for transactions','memory for statements',],

        fi

        chart_libs_reload=$(grep -i chart_libs_reload $chart_settings_file | awk -F '=' '{print $2}')
        [[ -z "$chart_libs_reload" ]] && chart_libs_reload=0 # default: we suppose that basic libaries already loaded in the <HEAD> section of web page.
        
        chart_only_show=$(grep -i chart_only_show $chart_settings_file | awk -F '=' '{print $2}') # do we show only chart, without table ? Usually this is NO.
        [[ -z "$chart_only_show" ]] && chart_only_show=0

        chart_title=$(grep -i chart_title $chart_settings_file | awk -F '=' '{print $2}') # "Performance per minute, chart"
        href_name=$(grep -i href_name $chart_settings_file | awk -F '=' '{print $2}') # Name of HTML-anchor to quick-jump by click on inner URL
        href_title=$(grep -i href_title $chart_settings_file | awk -F '=' '{print $2}') # Name of inner URL for user

        chart_div_wid=$(grep -i chart_div_wid $chart_settings_file | awk -F '=' '{print $2}')
        chart_div_hei=$(grep -i chart_div_hei $chart_settings_file | awk -F '=' '{print $2}')
        [[ -z "$chart_div_wid" ]] && chart_div_wid=1200
        [[ -z "$chart_div_hei" ]] && chart_div_hei=350

        chart_inline_block=$(grep -i chart_inline_block $chart_settings_file | awk -F '=' '{print $2}')
        [[ "$chart_inline_block" == "1" ]] && div_inline_expr="display: inline-block;"

        axis_color=$(grep -i axis_color $chart_settings_file | awk -F '=' '{print $2}')
        [[ -z "$axis_color" ]] && axis_color=DarkOliveGreen

        # https://developers.google.com/chart/interactive/docs/gallery/areachart#Configuration_Options 
        # https://stackoverflow.com/questions/786789/vertical-labels-with-google-charts-api
        # draw the horizontal axis text at an angle, to help fit more text along the axis
        # attribute: slantedText, value: true
        x_axis_slanted_labels=$(grep -i x_axis_slanted_labels $chart_settings_file | awk -F '=' '{print $2}') # must be STRING with value: 'true' or 'false'

        # Additional filter for records to be shown in chart (actual for perf per minute: we have to skip from there WARM_TIME phase).
        ### x_values_skip_list=$(grep -i x_values_skip_list $chart_settings_file | awk -F '=' '{print $2}') # ,WARM_TIME,
        x_values_skip_pattern=$(grep -i x_values_skip_pattern $chart_settings_file | awk -F '=' '{print $2}') # OVERALL

        chart_type=$(grep -i chart_type $chart_settings_file | awk -F '=' '{print $2}')
        [[ -z "$chart_type" ]] && chart_type=ScatterChart
        
        # { left:60, right:5, width:"100%", } -- values for 'chartArea:', useful to reduce margins around chart
        chart_area_options=$(grep -i chart_area_options $chart_settings_file | awk -F '=' '{print $2}')

        curve_type=$(grep -i curve_type $chart_settings_file | awk -F '=' '{print $2}')
        point_size=$(grep -i point_size $chart_settings_file | awk -F '=' '{print $2}')

	# Create data table to be displayed. Add 1st element to it: legend of columns.
	cat <<- EOF >>$tmp_chart_data
	    var data = google.visualization.arrayToDataTable([
	        ${legend_expr}
	EOF
    fi

	cat <<-EOF >$sql_temp
		set sqlda_display on;
		set planonly;
	EOF
    cat $sql_in >> $sql_temp


    ################################################################
    ### call isql for get SQLDA and parse column names and types ###
    ################################################################
    #set -x
    $isql_name $dbconn $dbauth -i $sql_temp 1>$tmp_sqlda 2>$sql_err
    #set +x

    if [[ -s "$sql_err" ]]; then
        msg="PREPARING QUERY FAILED:"
        echo $msg
        cat $sql_temp
        cat $sql_err
        echo "ABEND. JOB TERMINATED."

        echo $htm_repn $msg $htm_repc >>$tmp_html
        echo "<pre>" >>$tmp_html
        add_html_text $sql_temp $tmp_html 0
        add_html_text $sql_err $tmp_html 0 "\$css\$fault\$"
        echo "</pre>" >>$tmp_html
        cat $tmp_html >> $htm_file

        exit 1

    fi

    # Construct list of columns where data should be right-aligned (in html table cell) because of their NUMERIC types:
    pass_1st_sqltype=0
    num_types=" SHORT LONG INT64 DOUBLE LONG FLOAT DECFLOAT INT128"
    num_list=,
    while read line; do
        if [[ "$line" == *" sqltype: "* ]]; then
            pass_1st_sqltype=1

            # "01: sqltype: 448 VARYING Nullable --> 01, etc
            col_indx=$(echo "$line" | cut -d ':' -f1)

            # "01: sqltype: 448 VARYING Nullable --> VARYING
            # "01: sqltype: 580 INT64 scale: -2 subtype: 1 len: 8" --> INT64
            col_type=$(echo "$line" | cut -d ' ' -f4)
            if [[ "$num_types" == *" $col_type"* ]]; then
                num_list=${num_list}${col_indx},
            fi
        fi
    done < <( cat $tmp_sqlda )
    # result: num_list=,03,07,08, - with leading zeroes.
    # Remove all leading zeroes from each numeric index:
    # https://stackoverflow.com/questions/13210880/replace-one-substring-for-another-string-in-shell-script/13210909
    # https://www.gnu.org/software/bash/manual/bash.html#Shell-Parameter-Expansion
    num_list="${num_list//,0/,}"
    # result: num_list=,3,7,8, etc -- list of positions where columns have any type of NUMERIC family.

    tho="<th>"
    thc="</th>"
    tro="<tr>"
    trc="</tr>"
    tdo="<td>"
    tdc="</td>"
    tdno="<td align=right>"
    tdnc="</td>"

    echo "<table border="1" cellpadding="3">" >>$tmp_html
    echo $tro>>$tmp_html

    # Extract column aliases for printing TABLE header
    # FB 2.5:
    # :  name: (12)WORKING_MODE  alias: (8)CATEGORY
    # :  name: (5)MCODE  alias: (7)SETTING
    # :  name: (6)SVALUE  alias: (3)VAL
    #^    ^            ^---^        ^
    #a    b              c          d
    #
    # FB 3.0:
    # :  name: WORKING_MODE  alias: CATEGORY
    # :  name: MCODE  alias: SETTING
    # :  name: SVALUE  alias: VAL
    #^    ^       ^---^        ^
    #a    b         c          d
    # grep -E "name:[[:space:]]+.*[[:space:]]+alias:[[:space:]]" $tmp_sqlda > $sql_log
    
    col_indx=1
    while read line; do
            # Get LAST word of this line:
            fld_name="$(echo $line | awk -F[' ()'] '{print $NF}')"

            if [[ "$fld_name" == "alias:" ]]; then
                echo ${tho} " " ${thc} >> $tmp_html
                # select 1 as " " from rdb$database ==> 
                #   :  name: CAST  alias:
                # (i.e. without field name! string finishes with word 'alias:')
                fld_name=NO_NAMED_COLUMN
            else
                # FB 2.5+ :  name: (3)page cache memo used  alias: (3)page cache memo used
                # FB 3.0+ :  name: page cache memo used  alias: page cache memo used

                # echo $line | grep -o "${delimiter_word}.*" -->   alias: (3)page cache memo used /or/   alias: page cache memo used
                # cut -d' ' -f3-  --> remove leading space and "alias:", leave all other words.
                # NB: we have to use '-f3-' if delimiter word contains leading space! Otherwise one need use -f2-

                delimiter_word=" alias: " # ::: NB ::: we add leading space character here!
                if [[ "$fb" == "25" ]]; then
                    fld_name=$( echo $line | grep -o "${delimiter_word}.*" | cut -d' ' -f3- | cut -d')' -f2- )
                else
                    fld_name=$( echo $line | grep -o "${delimiter_word}.*" | cut -d' ' -f3- )
                fi
            fi
            # result: fld_name has value equal to query column, including case when it contains spaces:
            echo ${tho}${fld_name}${thc} >> $tmp_html

            if [[ $col_indx -eq 1 ]]; then
                fld_first=$fld_name
            fi
            fld_last=$fld_name
            col_indx=$((col_indx+1))
    done < <( grep -E "name:[[:space:]]+.*[[:space:]]+alias:[[:space:]]" $tmp_sqlda )
    echo $trc>>$tmp_html

    # Inject SET LIST ON in the SQL that will be executes, disable all "SET LIST OFF":
    rm -f $sql_temp
    echo "SET LIST ON; -- NOTE: injected auto by  ${BASH_SOURCE[0]}, Routine $FUNCNAME" >>$sql_temp
    while read line; do
        if echo $line | grep -q -E -i "set[[:space:]]+list[[:space:]]+off"; then
            echo "-- disabled by ${BASH_SOURCE[0]} -- $line" >> $sql_temp
        else
            echo "$line" >> $sql_temp
        fi
    done < <( cat $sql_in )
    # result: SQL is prepared for execution in mode SET LIST ON.

    ######################################
    ### call isql for show report data ###
    ######################################
    $isql_name $dbconn $dbauth -i $sql_temp 1>$sql_log 2>$sql_err

#if [[ -f ${chart_settings_file} ]]; then
#echo check $sql_log:
#echo ::::::::::::::::::::::::::
#cat -n $sql_log
#echo ::::::::::::::::::::::::::
#fi

    chart_record_elem_count=0
    while read line; do
        # Get field name without trailing spaces:
        fld_name=$(echo ${line:0:31} | sed 's/ *$//g')

        # with preserving trailing spaces: "${line:0:31}"
        if [[ "$fld_name" == "$fld_first" ]]; then
            # We about to start print 1st column of row. Put <TR> tag:
            echo $tro >> $tmp_html
            fld_num=1
        fi
        # do NOT - already was done, see above -- echo -n ${tdo}${fld_name}${tdc} >> $tmp_html

#if [[ -f ${chart_settings_file} ]]; then
#  echo ::::::::::::::::::::::::::::::::::::::::::::::::::::
#  echo start of loop on lines got from grep . $sql_log
#  echo cols_for_data=$cols_for_data
#  echo x_axis_field=.${x_axis_field}.
#  echo ++++++++++++++++++++++
#  echo fld_name=.${fld_name}.
#  echo fld_first=.${fld_first}.
#  echo ++++++++++++++++++++++
#  if [[ "${fld_name^^}" == "${x_axis_field^^}" ]]; then
#    echo this is field for SHOW in X-coord
#  else
#    echo this is NOT of X-coord
#  fi
#fi

        # Get SUBSTRING, starting from 32nd character:
        ###############
        cell=${line:32}

        if [[ "$cell" == *"\$css\$error\$"* ]]; then
            ccss="${cell/\$css\$error\$/}"
            cell="<span class=\"error\">$ccss</span>"
        elif [[ "$cell" == *"\$css\$warning\$"* ]]; then
            ccss="${cell/\$css\$warning\$/}"
            cell="<span class=\"warning\">$ccss</span>"
        elif [[ "$cell" == *"\$css\$success\$"* ]]; then
            ccss="${cell/\$css\$success\$/}"
            cell="<span class=\"success\">$ccss</span>"
        fi

        if [[ "$num_list" == *",$fld_num,"* ]]; then
            # this is column which belongs to NUMERIC DATATYPE family.
            # We have to adjust field content to right border of the cell.
            echo ${tdno}"${cell}"${tdnc} >> $tmp_html
        else
            echo ${tdo}"${cell}"${tdc} >> $tmp_html
        fi

        if [[ "$fld_name" == "$fld_last" ]]; then
            # Completed output for all columns of row: put </TR> tag
            echo $trc >> $tmp_html
        fi

        if [[ -f ${chart_settings_file} ]]; then 
            ##### prev: if [[ ! -z $x_axis_field && ! -z $y_axis_field ]]; then
            if [[ "${fld_name^^}" == "${x_axis_field^^}" ]]; then
                if [[ "$num_list" == *",$fld_num,"* ]]; then
                    # this column belongs to NUMERIC DATATYPE family.
                    # We have to write ts value 'as is', without any additions:
                    chart_point_x_value=${cell}
                else
                    # This field datatype is NOT numeric (most of all this is timestamp).
                    # We have to enclose its value into single quotes:
                    chart_point_x_value=\'${cell}\'
                fi
                chart_record_elem_count=$(( chart_record_elem_count+1 ))
                chart_record_data_array="        ,[${chart_point_x_value}"
            fi
            # result: defined X-coord of point to be shown.

            if [[ "${fld_name^^}" == "${y_axis_field^^}" ]]; then
                chart_point_y_value=${cell}
            fi

            if [[ "${cols_for_data^^}" == *",'${fld_name^^}',"* ]]; then
                # Example of cols_for_data: [,'metadata cache memo used','memo used by attachments','memo used by transactions','memo used by statements',]
                chart_record_elem_count=$(( chart_record_elem_count+1 ))
                if [[ "${cell}"  == "<null>" ]] ; then
                    chart_point_y_value=0
                else
                    chart_point_y_value=${cell}
                fi

                chart_record_data_array="${chart_record_data_array}, ${chart_point_y_value}"
#echo fld_name=$fld_name
#echo cell=.${cell}.
#echo  chart_point_y_value=$chart_point_y_value
#echo one of Y_points is defined: chart_record_data_array=$chart_record_data_array
            else
                :
#echo field $fld_name NOT from list cols_for_data=$cols_for_data
            fi
#echo chart_record_elem_count=$chart_record_elem_count
#echo y_charts_count=$y_charts_count            
            
            if [[ $chart_record_elem_count -eq $(( y_charts_count+1 ))  ]] ; then

                if [[ "${x_values_skip_pattern^^}" == *",${chart_point_x_value^^},"* ]]; then

                    :

                elif [[ -n "${x_values_skip_pattern}" && "${chart_point_x_value^^}" == *"${x_values_skip_pattern^^}"* ]]; then
                    # 12.05.2020.
                    # Ubuntu 18.04 will return TRUE when string is verified to be similar to pattern
                    # and this pattern is EMPTY string *and* uppercased (^^).
                    # For this reason we have to check that $x_values_skip_pattern is not empty
                    # before we do further check whether it is included in $chart_point_x_value.
                    # ONCE AGAIN: expression "${foo^^}" == *"^^"* will be TRUE in Ubuntu but FALSE on Cantos!

                    :

                else
                    echo "${chart_record_data_array} ]" >>$tmp_chart_data
                fi
                chart_record_elem_count=0
                unset chart_record_data_array
            fi
        fi

        fld_num=$((fld_num+1))

    done < <( grep . $sql_log )
    echo "</table>" >>$tmp_html

    if [[ -f ${chart_settings_file} ]]; then
        # $tmpdir/make_html_chart_data.tmp
        # End of data table:
	cat <<- EOF >>$tmp_chart_data
	    ]);
	EOF
    fi


    if [[ -s "$sql_err" ]]; then
        echo $htm_repn DATA PROCESSING FAULT: $htm_repc >>$tmp_html
        echo "<pre>" >>$tmp_html
        add_html_text $sql_temp $tmp_html 0
        add_html_text $sql_err $tmp_html 0 "\$css\$fault\$"
        echo "</pre>" >>$tmp_html
    fi

    if [[ -f ${chart_settings_file} ]]; then
        #x_axis_field=$(grep -i x_axis_field $chart_settings_file | awk -F '=' '{print $2}')
        #y_axis_field=$(grep -i y_axis_field $chart_settings_file | awk -F '=' '{print $2}')

	cat <<-EOF >>$tmp_chart_html
	$( [[ -n "${href_title}" ]] && echo "<h3><a name=${href_name}> ${href_title} </a></h3>" )

	<div id="${draw_func_name}_div" style="width: ${chart_div_wid}px; height: ${chart_div_hei}px;${div_inline_expr}"></div>

        $( [[ $chart_libs_reload -eq 1 ]] && echo "<script type="text/javascript" src="https://www.gstatic.com/charts/loader.js"></script>" )

	<script type="text/javascript">
	    $( [[ $chart_libs_reload -eq 1 ]] && echo "google.charts.load('current', {'packages':['corechart']});" )

	    // see settings here: https://developers.google.com/chart/interactive/docs/
	    google.charts.setOnLoadCallback(${draw_func_name});
	    function ${draw_func_name}() {
	        // Add data to temp html for drawing chart:
	        // ----------------------------------------
	        $(cat $tmp_chart_data)
	EOF
	
	# 16.05.2020: add formetting to number values:
        # pattern: '0';   pattern: '0.00',negativeColor: 'red';   fractionDigits: 4;   etc
        # y_format_list=$(grep -i y_format_list $chart_settings_file | awk -F '=' '{print $2}' | sed 's/ *$//g')
        if [[ -n "${y_format_list}" ]]; then
            IFS=';' read -r -a y_format_array <<< "${y_format_list}"
            col_indx=1
            for e in "${y_format_array[@]}"
            do
                # example: new google.visualization.NumberFormat({ pattern: '0.000' }).format(data, 1); -- format SECOND column of data array
                echo "        new google.visualization.NumberFormat({ ${e} }).format(data, $col_indx);" >>$tmp_chart_html
                col_indx=$((col_indx+1))
            done
        fi
	
	if [[ "${chart_type}" == "PieChart" ]]; then
		cat <<-EOF >>$tmp_chart_html
	        var options = {
                        title: '${chart_title}'
                    };
		EOF
	else
		cat <<-EOF >>$tmp_chart_html
	        var options = {
                    title: '${chart_title}',
                    $( [[ -n "${curve_type}" ]] && echo curveType: \'${curve_type}\', )
                    $( [[ -n "${point_size}" ]] && echo pointSize: ${point_size}, )
                    $( [[ -n "${legpos_expr}" ]] && echo ${legpos_expr}, )
                    $( [[ -n "${color_expr}" ]] && echo ${color_expr}, )
                    $( [[ -n "${chart_area_options}" ]] && echo "chartArea:${chart_area_options}," )

                    hAxis: {
                         title: '${x_axis_title}',
                         format: '0',
                         textStyle: {
                           color: '$axis_color',
                           bold: false,
                           italic: false,
                           fontSize: 10
                         },
                         $( [[ -n "${x_axis_slanted_labels}" ]] && echo slantedText: ${x_axis_slanted_labels} )
                    },
                    vAxis: {
                         title: '${y_axis_title}',
                         minValue: 0,
                         $( [[ -n "${y_scale_type}" ]] && echo "scaleType: '${y_scale_type}'," )
                         textStyle: {
                           color: '$axis_color',
                           bold: false,
                           italic: false,
                           fontSize: 10
                         }
                    }
	        }
		EOF
	fi
	# chart_type = PieChart --> true / false

	cat <<-EOF >>$tmp_chart_html
	        // var chart = new google.visualization.ScatterChart(document.getElementById('${draw_func_name}_div'));
	        var chart = new google.visualization.${chart_type}(document.getElementById('${draw_func_name}_div'));
	        chart.draw(data, options);
	    }
	</script>
	EOF

        if [[ $chart_only_show -eq 1 ]]; then
            # SKIP from showing html table, only chart is interested here:
            mv --force $tmp_chart_html $tmp_html
        else
            # Show both the table and chart
            cat $tmp_chart_html >> $tmp_html
        fi

    fi

    cat $tmp_html >> $htm_file

    rm -f $sql_temp $sql_log $sql_err $tmp_sqlda $tmp_nums $tmp_html $tmp_chart_data

}
# end of: add_html_table()
# -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+


#.......................................... m a i n     p a r t ................................

export shname=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)/`basename "${BASH_SOURCE[0]}"`
export shdir=$(cd "$(dirname "$0")" && pwd)

[ -z $1 ] && msg_noarg && exit 1

# limits for log of work and errors
# (zap if size exceed and fill again from zero):
maxlog=25000000
maxerr=25000000

cfg=$1
sql=$2
prf=$3 # prefix for temp files name which will be created by every ISQL session; based on $HOSTNAME value, sample: '/var/tmp/logs.oltp30/oltp30_some_box.our_firm.ru'
sid=$4 # ISQL window (session) sequential number
rpt=$5 # final report where SID=1 has to ADD info about performance ($tmpdir/oltp30.report.txt)
fname=$6 # config parameter 'file_name_with_test_params': regular | benchmark
build=$7
conn_pool_support=$8
ainfo=$9 # file_name_this_host_info: 'cpu_2x4_ram_16' etc

#echo build=$build

# 26.10.2018: number of ISQL sessions can be greater than 999.
prf=$prf-$(echo `printf "%04d" $sid`)

# log where current acitvity of this ISQL will be:
log=$prf.log

# log where ERRORS will be for this ISQL:
err=$prf.err

# cumulative log with brief info about running process state:
sts=$prf.state.txt

rm -f $log $err $sts
>$log
>$err

#echo -e Config file \>$cfg\< parsing result:
echo 
echo log=$log
sho "SID=$sid. Read config file $cfg. Log: $log" $log

shopt -s extglob

######################
# AGAIN RE-READ CONFIG
######################
while IFS='=' read lhs rhs
do
    if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
        # | sed -e 's/^[ \t]*//'
        lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
        rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
        [[ ${rhs:0:1} == "$" ]] && rhs=$(eval "echo $rhs")
        # echo "lhs=.${lhs}. ; rhs=.${rhs}."
        declare $lhs=$rhs
        if [ $? -gt 0 ]; then
          echo +++ ACHTUNG +++ SOMETHING WRONG IN YOUR CONFIG FILE
          exit
        fi
        # echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
    fi
done < <(awk '$1=$1' $cfg  | grep "^[^#]")
# < <( sed -e 's/^[ \t]*//' $cfg | grep "^[^#;]" )

if [ "$clu" != "" ]; then
    # Name of ISQL on Ubuntu/Debian when FB is installed from OS repository
    # 'isql-fb' etc:
    echo Config contains custom name of command-line utility for interact with Firebird.
    echo Parameter: \'clu\', value: \|$clu\|
else
    echo Using standard name of command-line utility for interact with Firebird: 'isql'
    clu=isql
fi
isql_name=$fbc/$clu

sho "SID=$sid. Config file $cfg parsed OK." $log


if [ $is_embed = 1 ]; then
  dbauth=
  dbconn=$dbnm
else
  dbauth="-user ${usr} -password ${pwd}"
  dbconn=$host/$port:$dbnm
fi

# since 12.08.2018: make each SID run its own 'starter SQL' script which assigns
# session-level context variable 'WORKER_SEQUENTIAL_NUMBER' for this SID and
# only after this launches 'main' SQL: $tmpdir/sql/tmp_random_run.sql
# This allows this SID be known in procedural code and, in turn, take for processing
# documents with ID that can be taken only by this SID. Actual only when config
# parameter 'separate_workers' equals to 1.
run_isql="$isql_name $dbconn -now -q -n -pag 9999 -i $sid_starter_sql $dbauth"

##############################################################################################################
# 12.08.2018
# Define name of .sql script that will be launched by THIS - and only this - command window.
# This is name like "/var/tmp/logs.oltp30/sql/tmp_sid_197.starter.sql" etc, and it will create CONTEXT VAR
# with session-level scope. Main script will be invoked from THIS starter, thus it will know
# sequential ID of THIS command window: 1, 2, 3, ..., $winq


sid_starter_sql=$(dirname $sql)/tmp_starter.$(echo `printf "%04d" $sid`).sql

sho "SID=$sid. Creating starter script sid_starter_sql='$sid_starter_sql'" $log
rm -f $sid_starter_sql


conn_as_locksmith=1
if [[ "$fb" != "25" && -n "${mon_query_role}" && -n "${mon_usr_prefix}" ]]; then
    # If FB = 3.x+ then we create non-privileged users in all cases except mon_unit_perf=0
    # Working as NON_dba is much closer to the real-world applications then doing common business tasks as SYSDBA.
    if [[ $mon_unit_perf -eq 1 ]]; then
        # mon_unit_perf=1 requires that *each* worker will gather monitoring data
        # before and after each selected business action, i.e. very frequently.
        # Despite that every worker is interesting only for data related to himself
        # (i.e. makes filter 'where mon$attachment_id = curent_connection'), every
        # mon$ gathering involves all other workers to make 'dumps' of their state
        # to the monitoring data pool.
        # This leads to EXTREMELY high penalty of performance for approx. 15 times.
        # -----------------------
        # Engine FB 3.x was optimized for this case: if monitoring data are queried
        # by non-privileged user then all connections from other users will not take
        # in account this event and their work will continue without any delay for
        # dumping data for this user.
        # See: http://sourceforge.net/p/firebird/code/62745
        # "Tag the shmem session clumplets with username. This allows much faster lookups for non-locksmith users."
        # -----------------------
        # Benchmark shows that cost of monitoring in this case is almost zero:
        # overall performance score is equal to the case when mon_unit_perf=0.
        # For this reason ALL attachments must connect as NON-privileged users
        # (with different names for each connection):
        conn_as_locksmith=0
    elif [[ $mon_unit_perf -eq 2 ]]; then
        if [[ $sid -eq 1 ]]; then
            # First ISQL session must have mon$ info for *ALL* attachments.
            # This means that for SID=1 we must play as SYSDBA:
            conn_as_locksmith=1
        else
            # Other attachments do NOT query monitoring tables.
            # They must connect as NON-privileged users
            # (with different names for each connection):
            conn_as_locksmith=0
        fi
    elif [[ $mon_unit_perf -eq 0 ]]; then
        ####################################################################
        ### ::: NB ::: mon_unit_perf = 0 --> all sessions work as SYSDBA ###
        ####################################################################
        # See also: 1run_oltp_emul.sh, routine: adjust_grants
        conn_as_locksmith=1
    fi
fi

cat <<- EOF >> $sid_starter_sql
	-- Generated $(date +'%d.%m.%Y %H:%M:%S') by $shname.
	-- Do NOT edit. This script will be removed after test.
EOF

if [[ $conn_as_locksmith -eq 0 ]]; then
    v_user_for_sid=${mon_usr_prefix}$(printf "%04d" $sid)
    v_pswd_for_sid='123'
	cat <<- EOF >> $sid_starter_sql
	-- ##########################################################################################################
	-- ###                   w o r k   a s   n o n - p r i v i l e g e d   u s e r                            ###
	-- ##########################################################################################################
	-- Parameter 'mon_unit_perf' is not zero, parameters 'mon_usr_prefix' and 'mon_query_role' are UNCOMMENTED,
	-- i.e. they values are not empty: $mon_usr_prefix, $mon_query_role.
	-- All sessions $( [[ $mon_unit_perf -eq 2 ]] && echo except SID=1 ) will work as NON-privileged users.
	-- Queries to monitoring tables by each session will NOT force all other sessions to make delays for transfer
	-- their own monitoring data into the common pool. Performance will be SIGNIFICANTLY INCREASED because of this.
	-- See: http://sourceforge.net/p/firebird/code/62745
	-- "Tag the shmem session clumplets with username. This allows much faster lookups for non-locksmith users."

	rollback;
	connect '$host/$port:$dbnm' user '$v_user_for_sid' password '$v_pswd_for_sid' role '$mon_query_role';
	EOF
else
	if [[ "$fb" != "25" ]]; then
		cat <<- EOF >> $sid_starter_sql
		-- #############################################################################
		-- ###                   w o r k   a s   S Y S D B A                         ###
		-- #############################################################################
		EOF
	  if [[ $mon_unit_perf -eq 0 ]]; then
		echo -e "-- NOTE. config parameter mon_unit_perf = 0. All sessions will work as '$usr'" >> $sid_starter_sql
	  elif [[ $mon_unit_perf -eq 1 ]]; then
		cat <<- EOF >> $sid_starter_sql
		-- NOTE: config parameter 'mon_unit_perf' = 1 but parameters 'mon_usr_prefix' and 'mon_query_role'
		-- are undefined (commented). All ISQL sessions will work as '$usr'.
		-- Queries to monitoring tables by each session will FORCE ALL other connections to transfer their own
		-- monitoring data into the common monitor pool thus performance will be SIGNIFICANTLY REDUCED.
		EOF
	  elif [[ $sid -eq 1 && $mon_unit_perf -eq 2 ]]; then
		cat <<- EOF >> $sid_starter_sql
			-- NOTE. Text configuration parameter mon_unit_perf = 2.
			-- First launched ISQL session will work as SYSDBA because it will
			-- query monitoring data about ALL other workers.
		EOF
	  fi
	else
		echo -e "This is FB 2.5, monitoring was not improved. All sessions will work as SYSDBA" >> $sid_starter_sql
	fi
	cat <<- EOF >> $sid_starter_sql
	rollback;
	connect '$host/$port:$dbnm' user '$usr' password '$pwd';
	EOF
fi

cat <<- EOF >> $sid_starter_sql
	set term ^;
	execute block as
	begin
	    -- Define 'sequential number' of current ISQL session and make it be known 
	    -- for main script and every business operations that are called from there:
	    -- NB: name 'WORKER_SEQUENTIAL_NUMBER' is used in procedures for storing
	    -- value in doc_list.worker_id for possible separation of scope that is avaliable
	    -- for each ISQL session. Purpose - reduce frequency of lock conflicts.
	    rdb\$set_context( 'USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER', '$sid' );
	    rdb\$set_context( 'USER_SESSION', 'WORKER_SEQ_NUMB_4RESTORE', '$sid' );
	end^
	set term ;^
	-- Call main script that was created on prepare phase of oltp-emul scenario:
	in $sql;
EOF
##############################################################################################################

# 17.05.2020: authentification is performed now in $sid_starter_sql:
run_isql="$isql_name -now -q -n -pag 9999 -i $sid_starter_sql"

cat << EOF >>$sts
$(date +'%Y.%m.%d %H:%M:%S'). Batch running now: $0 - check start command:
--- begin ---
$run_isql 1>>$log 2>>$err
--- end ---
EOF

[[ $sid = 1 ]] &&  echo This session *WILL* do performance report after test make selfstop.>>$sts

tmpauxsql=$tmpdir/tmp_$sid.aux.sql
tmpauxlog=$tmpdir/tmp_$sid.aux.log
tmpauxerr=$tmpdir/tmp_$sid.aux.err
tmpauxtmp=$tmpdir/tmp_$sid.aux.tmp
tmpcharts=$tmpdir/chart_settings.tmp

#tmpsidsql=$tmpdir/tmp_$sid.sql
#tmpsidlog=$tmpdir/tmp_$sid.log
#tmpsiderr=$tmpdir/tmp_$sid.err

tmpsidsql=$(dirname $sql)/tmp_$sid.sql
tmpsidlog=$(dirname $sql)/tmp_$sid.log
tmpsiderr=$(dirname $sql)/tmp_$sid.err

fblog_beg=$tmpdir/fb_log_when_test_started.$fb.log
fblog_end=$tmpdir/fb_log_when_test_finished.$fb.log

if [ $sid -eq 1 ]; then
  [[ $fb -eq 25 ]] && get_log_switch=action_get_ib_log || get_log_switch=action_get_fb_log

  run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth $get_log_switch"
  msg="$(date +'%Y.%m.%d %H:%M:%S'). SID=$sid. Gathering firebird.log before opening 1st window for obtaining new text which will appear in it during test."
  echo
  echo $msg
  echo $msg >>$rpt
  echo Command: $run_fbs >>$rpt
  $run_fbs 1>$fblog_beg 2>>$rpt
  echo Got:>>$rpt
  ls -l $fblog_beg 1>>$rpt 2>&1
  sho "SID=$sid. Extracted firebird.log BEFORE test: $(ls -l $fblog_beg)" $log
fi

if [ -z "$sleep_min" ]; then
    echo Parameter \'sleep_min\' was not defined in config and is assigned to 1.
    sleep_min=1
fi

random_delay=1
min_delay=$(( 1 + sid/25 ))
max_delay=$(( 2 + sid/max_cps ))

use_cps=0
if [[ $max_cps -ge 10 && $max_cps -le 100 ]]; then
    # Max rate of new attachments appearance set to some reasonable value.
    use_cps=1
fi

if [ $use_cps -eq 1 ]; then
    if [ $winq -gt $max_cps ]; then
        min_delay=$(( 1 + sid/max_cps ))
        max_delay=$(( 1 + sid/max_cps ))
        sho "SID=$sid. Use parameter 'max_cps'=$max_cps connections per second for evaluating delay." $sts
    else
        min_delay=1
        max_delay=4
        sho "SID=$sid. Number of sessions is too small, delay will be from $min_delay fo $max_delay seconds." $sts
    fi
else
    if [ $max_cps -eq 0 ]; then
        min_delay=0
        max_delay=0
        sho "SID=$sid. Config parameter 'max_cps' is 0. Heavy workload will be for big number of sessions." $sts
    else
        sho "SID=$sid. Config parameter 'max_cps' is $max_cps - out of reasonable scope. Delay will be from $min_delay fo $max_delay seconds." $sts
    fi
fi

sho "ISQL session SID=$sid. Start loop until limit of $(( warm_time + test_time )) minutes will expire." $log

packet=1
while :
do

  if [ $sid -gt 1 ]; then
      if [ $packet -eq 1 ]; then
          sho "SID=$sid. Point before execution packet $packet. Evaluate required delay before attempt to make attachment." $sts 
          if [ $min_delay -eq $max_delay ]; then
              random_delay=$min_delay
              msg_suff="Fixed delay for $min_delay seconds"
          else
              random_delay=$(( $min_delay+ ( RANDOM % (1+$max_delay-$min_delay) ) ))
              msg_suff="Random delay for $random_delay seconds from scope $min_delay ... $max_delay"
          fi
          sho "SID=$sid. $msg_suff" $sts

          sleep $random_delay
          sho "SID=$sid. Pause finished. Start ISQL to make attachment and work..." $sts
      else
          sho "SID=$sid. Packet=$k. Pause is skipped for all packets starting from 2nd." $sts
      fi
  else
      # 26.10.2018. If SID=1 will get client error and this message in STDERR:
      #     Statement failed, SQLSTATE = 08004
      #     connection rejected by remote interface
      # -- then no report will exist after test finish!
      sho "SID=1. SKIP pause before attempt to attach. This session will make reports thus we allow it to make attach w/o any delay." $sts
  fi

  if [ -s $log ]; then
    if [ $(stat -c%s $log) -gt $maxlog ]; then

      sho "SID=$sid. Size of $log = $(stat -c%s $log) - exceeds limit $maxlog, remove it" $sts
      rm -f $log $tmpsidlog $tmpsiderr
    fi
  fi
  if [ -s $err ]; then
    if [ $(stat -c%s $err) -gt $maxerr ]; then
      sho "SID=$sid. Size of $err = $(stat -c%s $err) - exceeds limit $maxerr, remove it" $sts
      rm -f $err
    fi
  fi

  sho "SID=$sid. Starting packet $packet." $sts
	cat <<- EOF >>$tmpsidlog
		RUNCMD: $run_isql
		STDLOG: $log
		STDERR: $err
	EOF

  cat $tmpsidlog
  cat $tmpsidlog>>$sts
  rm -f $tmpsidlog

  ##############################
  ###    R U N     I S Q L   ###
  ##############################
  $run_isql 1>>$log 2>>$err

  sho "SID=$sid. Finish isql, packet No. $packet" $sts

  echo ------ last lines in isql STDOUT log: ------------>>$sts
  tail -15 $log | grep . | sed -e 's/^/    /' >>$sts
  echo ------ last lines in isql STDERR log: ------------>>$sts
  tail -15 $err | grep . | sed -e 's/^/    /' >>$sts
  echo -------------------------------------------------->>$sts

  if grep -E "database.*shutdown" $err > /dev/null ; then
      sho "SID=$sid. DATABASE SHUTDOWN DETECTED, session has finished its job." $sts
      ###################################################
      # ....................  e x i t ...................
      ###################################################
      break
  fi

  # 27.05.2016 Check whether server crashed during this round:
  # count number of lines 'error reading / writing from/to connection'
  # in the %err% file. If this number exceeds config parameter then
  # we TERMINATE further execution of test.

  crash_pattern="SQLSTATE = 08003\|SQLSTATE = 08006"
  crashes_cnt=$(grep -i -c -e "$crash_pattern" $err)

  # this variable will be changed in routine get_diff_fblog() if phrase about crash ("terminated abnormally")
  # will be detected in the difference file for $fblog_beg and $fblog_end.
  crash_during_run=0
  if [ $crashes_cnt -gt 5 ] ; then
      sho "SID=$sid. Connection problem detected at least $crashes_cnt times, pattern = $crash_pattern. Session has finished its job." $sts
      crash_during_run=1
  elif [ $crashes_cnt -gt 1 ]; then
      # When at least one of messages with SQLSTATE=08003 or 08006 appear we have to check
      # that there was no crash of firebird process since this test started. We can do it
      # by checking DIFFERENCE of $fblog_beg and $fblog_end for presence of string which
      # proves crash: firebird/fb_smp_server terminated abnormally. If such row exists then
      # test must be terminated ASAP, but *except* for SID=1 because it make final report.
      get_diff_fblog check_for_crash $fb $sid $fblog_beg $sts crash_during_run
      #                    1          2    3      4        5        6
      sho "Return to main code from get_diff_fblog: crash_during_run=$crash_during_run" $sts
  else
      sho "SID=$sid. No FB craches detected in $err." $sts
  fi

  if [[ $crash_during_run -eq 0 ]]; then

      # 42000 ==> -902 	335544569 	dsql_error 	Dynamic SQL Error
      # 42S22 ==> -206 	335544578 	dsql_field_err 	Column unknown
      # 42S02 ==> -204 	335544580 	table unknown: TMP // when forgen to add backstash befor tmp$foo
      # 22001 ==> arith overflow / string truncation
      # 39000 ==> function unknown: RDB // when forget to add backslash before rdb$get/rdb$set_context
      # 28000 ==> no permission for ... access to ... // 17.05.2020: OLTP_USER_nnnn via role WORKER instead of SYSDBA

      # Ubuntu + FB 2.5.4.x from repo: "42000" can be raised by user-defined-expection for unknown reason!!!
      # commented 01.06.2019 19:03: syntax_pattern="SQLSTATE = 42000\|SQLSTATE = 42S22\|SQLSTATE = 42S02\|SQLSTATE = 22001\|SQLSTATE = 39000"

      syntax_pattern="Dynamic SQL Error\|SQLSTATE = 42S22\|SQLSTATE = 42S02\|SQLSTATE = 22001\|SQLSTATE = 39000\|SQLSTATE = 28000"

      syntax_err_cnt=$(grep -i -c -e "$syntax_pattern" $err)
      if [ $syntax_err_cnt -gt 0 ] ; then
          sho "SID=$sid. DSQL errors occured at least $syntax_err_cnt times, pattern = $syntax_pattern. Session has finished its job." $sts
          grep -n -i -A5 -e "$syntax_pattern" $err 1>>$sts 2>&1

          remove_isql_logs=never

          ###################################################
          # ....................  e x i t ...................
          ###################################################
          break
      else
          sho "SID=$sid. No DSQL errors detected in $err." $sts
      fi

      run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth info_server_version info_implementation"
      cancel_test=0
      # 26.10.2018: unable to establish connect under extremely heavy workload, ~2000-3000 attachments.
      GET_FB_REPLY_MAX_TRIES=20
      for k in `seq $GET_FB_REPLY_MAX_TRIES`
      do
          if grep -i "test_was_cancelled" $log > /dev/null ; then
              msg="SID=$sid. Found sign of TEST CANCELLATION in STDOUT log, file $log."
              cancel_test=1
          elif grep -i "ex_test_cancel" $err > /dev/null ; then
              msg="SID=$sid. Found sign of TEST CANCELLATION in STDERR log, file $err."
              cancel_test=1
          fi
          if [ $cancel_test -eq 1 ]; then
              # ::: NB ::: do NOT forget double quotes here!
              sho "$msg" $sts
              break
          fi

          echo
          sho "SID=$sid. Check that FB is still alive: attempt to get server version using fbsvcmgr call. WAIT..." $sts
          #echo     Command: $run_fbs >>$sts
          #echo      STDLOG: $tmpsidlog >>$sts
          #echo      STDERR: $tmpsiderr >>$sts

          #######################################################################
          ###     f b s v c m g r   i n f o _ s e r v e r _ v e r s i o n     ###
          #######################################################################
          $run_fbs 1>$tmpsidlog 2>$tmpsiderr
          if [[ $k -gt 1 && $(stat -c%s $tmpsiderr) -eq 0 ]]; then
              sho "SID=$sid. Return to script. Problem RESOLVED after $k iterations." $sts
              echo Content of STDOUT received from fbsvcmgr:>>$sts
              echo ----------------------------------------->>$sts
              cat $tmpsidlog | sed -e 's/^/       /' >> $sts
              echo ----------------------------------------->>$sts
          else
              if [ $(stat -c%s $tmpsiderr) -gt 0 ]; then
                  sho "SID=$sid. Problem EXISTS. Size of logs: STDOUT=$(stat -c%s $tmpsidlog), STDERR=$(stat -c%s $tmpsiderr)" $sts
              else
                  sho "SID=$sid. Successful get FB version on first call." $sts
              fi
          fi

          #sho "SID=$sid. Size of logs: STDOUT=$(stat -c%s $tmpsidlog), STDERR=$(stat -c%s $tmpsiderr)" $sts
          # ::: NB ::: 26.10.2018
          # Under heavy workload (2500...3000 attachments) client can issue:
          # 'connection rejected by remote interface'
          # It is recommended to increase FB config parameter
          # connection_timeout in this case.
          # --------------------------------------------------------
          # When FB is really unavaliable then error message will be:
          # Unable to complete network request to host "localhost".
          # -Failed to establish a connection.  

          if [ -s $tmpsiderr ]; then
              sho "SID=$sid. Firebird is UNAVAILABLE. We have to check whether this problem relates to CLIENT or SERVER side." $sts
              cat $tmpsiderr
              echo Content of STDERR received from fbsvcmgr:>>$sts
              echo ----------------------------------------->>$sts
              cat $tmpsiderr | sed -e 's/^/       /' >> $sts
              echo ----------------------------------------->>$sts

              # Only 'connection rejected by remote interface' can be interpreted as TEMPORARY unavaliable!
              if grep -i "connection rejected" $tmpsiderr > /dev/null ; then
                  sho "Failure seems to be on CLIENT-SIDE." $sts
                  rm -f $tmpsiderr
                  if [ $k -eq $GET_FB_REPLY_MAX_TRIES ] ; then
                      ###################################################
                      # ....................  e x i t ...................
                      ###################################################
                      sho "SID=$sid exceeds limit $GET_FB_REPLY_MAX_TRIES for attempts to get reply from FB server. Job is terminated." $sts
                      rm -f $sid_starter_sql
                      exit
                  else
                      sho "Try to solve failure: iteration $k of total $GET_FB_REPLY_MAX_TRIES. Loop to next attempt after small pause." $sts
                      sleep 5
                      sho "Pause finished, LOOP to next iteration." $sts
                  fi
              else
                  ###################################################
                  # ....................  e x i t ...................
                  ###################################################
                  sho "Failure seems to be on SERVER-SIDE. Job is terminated" $sts
                  rm -f $tmpsiderr
                  rm -f $sid_starter_sql
                  exit
              fi
          else
              sho "SID=$sid. Firebird is alive, test can be continued." $sts
              cat $tmpsidlog>>$sts
              rm -f $tmpsidlog $tmpsiderr
              break
          fi
      done
  else
      sho "SID=$sid. FB crash or connection problem detected, set flag 'cancel_test' to 1" $rpt
      cancel_test=1
  fi
  # $crash_during_run -eq 0 or 1

  if [ $cancel_test -eq 1 ]; then

    sho "SID=$sid. Test has been CANCELLED." $sts

    # -------------------------------------------------------------------------
    # E X I T    i f   c u r r e n t    S I D     g r e a t e r   t h a n    1.
    # ~~~~~~~------------------------------------------------------------------
    if [ $sid -gt 1 ]; then
        sho "SID=$sid. Leave from loop because SID greater than 1." $sts
        if [[ "$remove_isql_logs" == "always" ]]; then
            rm -f $log $err $sts
        fi
        break
    fi

    plog=$rpt
    # ---- do NOT ---- rm $plog



    psql=$prf.performance_report.tmp

    run_fbs_dbattr="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth action_db_stats sts_hdr_pages dbname $dbnm"
    $run_fbs_dbattr 1>$tmpauxlog 2>$tmpauxerr
    can_shutdown=1
    # Attributes              multi-user maintenance, backup lock
    # Attributes              backup lock
    # Drop all attachments. DO NOT use 'delete from mon$attachments' here, it is often useless!
    if grep -q -i -e "attributes[[:space:]]\+.*backup[[:space:]]\+lock" $tmpauxlog ; then
        #    C:\FB\30SS\fbsvcmgr localhost:service_mgr user sysdba password masterkey action_properties prp_shutdown_mode prp_sm_multi prp_shutdown_db 0 dbname C:\FBTESTING\qa\misc\e30.fdb
        sho "SID=$sid. Database is in BACKUP LOCK state. We can change DB state to multi-user maintenance rather than full shutdown." $rpt
        run_fbs_dbshut="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth action_properties prp_shutdown_mode prp_sm_multi prp_shutdown_db 0 dbname $dbnm"
        # NOTE: attachments and statements will be dropped, but any SYSDBA can still make new attachments and launch new statements.
    else
        sho "SID=$sid. Forcedly drop all other attachments: change DB state to full shutdown." $rpt
        # rpt =$5 -- final report where sid N1 has to ADD info about performanc, its name: $tmpdir/oltpNN.report.txt
        run_fbs_dbshut="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth action_properties prp_shutdown_mode prp_sm_full prp_shutdown_db 0 dbname $dbnm"
    fi

    sho "SID=$sid. Command: $run_fbs_dbshut" $rpt 1
    # ---------------------------------------------------
    # t e m p - l y    s h u t d o w n    d a t a b a s e
    # ---------------------------------------------------
    $run_fbs_dbshut 1>$tmpauxerr 2>&1
    cat $tmpauxerr
    cat $tmpauxerr >>$rpt


    # 06.10.2020: FB can crash when try to change DB state to shutdown!
    # We have to check $tmpauxerr for presence of text like: "Error reading/writing data from/to the connection"
    # If such text presents then we have to try to write info about ABNORMAL finish into database!
    crash_on_db_shut=0
    if grep -q -m1 -i "error[[:space:]]\+\(reading\|writing\).*\(from\|to\).*connection" $tmpauxerr ; then
        crash_on_db_shut=1
    fi

    sho "SID=$sid. Done. Check DB header attributes:" $rpt 1
    run_fbs_dbattr="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth action_db_stats sts_hdr_pages dbname $dbnm"
    $run_fbs_dbattr 1>$tmpauxlog 2>$tmpauxerr
    cat $tmpauxerr
    cat $tmpauxerr >>$rpt
    grep -i attributes $tmpauxlog
    grep -i attributes $tmpauxlog 1>>$rpt

    rm -f $tmpauxlog $tmpauxerr

    # If we are here then one may sure that ALL attachments now are dropped and there is NO any activity of internal FB processes against DB.
    # Now we can turn DB online and continue work with it using only SINGLE attachment which SID=1

    if [[ $dbconn =~ .*localhost[/:]{1}.* || $dbconn =~ .*127.0.0.1[/:]{1}.* ]]; then
	#cat <<-EOF >$tmpauxtmp
	#	thread apply all bt
	#	shell $fbc/fb_lock_print -a -d $dbnm 1>$tmpdir/gdb-firebird-lock-print.txt 2>&1
	#	quit
	#	yes
	#EOF
	#gdb -q -x $tmpauxtmp $fbs/firebird $(pgrep firebird) 1>$tmpdir/gdb-firebird-stack-trace.txt 2>&1

        sho "SID=$sid. Check output of fb_lock_print: get header of LM for $dbnm:" $rpt
        while read line; do
            #sho "$line" $rpt
            echo -e "\t$line"
            echo $line >>$rpt
        done < <($fbc/fb_lock_print -c -d $dbnm)
        #$fbc/fb_lock_print -c -d $dbnm 1>$rpt 2>&1
    else
        sho "SID=$sid. Test uses REMOTE Firebird instance, utility fb_lock_print can not be used." $rpt
    fi
    #^-- [[ $dbconn =~ .*localhost[/:]{1}.* || $dbconn =~ .*127.0.0.1[/:]{1}.* ]]

    if [[ $can_shutdown -eq 1 ]]; then
        run_fbs_online="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth action_properties prp_db_online dbname $dbnm"
        sho "SID=$sid. Return DB to online state. Command: $run_fbs_online" $rpt 1
        # -----------------------------------
        # r e t u r n     D B     o n l i n e
        # -----------------------------------
        # NOTE: if DB was in 'backup lock' state then new attributes will not be seen in its header until nbackup -N.
        # This means that following command will show the same as previous. See CORE-6399
        $run_fbs_online 1>$tmpauxlog 2>$tmpauxerr
        cat $tmpauxerr
        cat $tmpauxerr >>$rpt
        sho "SID=$sid. Done. Check DB header attributes:" $rpt 1
        $run_fbs_dbattr 1>$tmpauxlog 2>$tmpauxerr
        grep -i attributes $tmpauxlog
        grep -i attributes $tmpauxlog 1>>$rpt
        rm -f $tmpauxlog $tmpauxerr
    fi

    rm -f $psql

	cat <<- "EOF" >>$psql
		set term ^;
		execute block as
		    declare c int;
		begin
		    -- Count records in order to remove all garbage in this table:
		    select count(*) from semaphores into c;
		end
		^
		set term ^;
		commit;
		
		set heading off;
		select 'Attachments that still alive:' as " " from rdb$database;
		set heading on;
		set list on;
		set blob all;
		set count on;
		select
		    a.mon$attachment_id as attachment_id
		    ,a.mon$server_pid as server_pid
		    ,a.mon$state as attachment_state
		    ,a.mon$remote_protocol as remote_protocol
		    ,a.mon$remote_address as remote_address
		    ,a.mon$remote_pid as remote_pid
		    ,a.mon$timestamp as attachment_timestamp
		    ,s.mon$state as statement_state
		    ,s.mon$timestamp as statement_timestamp
		    ,s.mon$sql_text as statement_sql
		from mon$attachments a
		left join mon$statements s on a.mon$attachment_id = s.mon$attachment_id
		where
		    a.mon$attachment_id != current_connection
		    and a.mon$remote_address is not null
		    and upper(s.mon$sql_text) not similar to upper('%execute[[:WHITESPACE:]]+block%')
		;
		set count off;
		set list off;
	EOF
	if [[ $crash_on_db_shut -eq 1 ]]; then
	    # 06.10.2020: update record in perf_log about test finish outcome:
	    # write info about FB crash when changed DB state to shutdown.
		cat <<- "EOF" >>$psql
			set list on;
			update perf_log set
			         stack = 'script: ${BASH_SOURCE[0]}, line: $LINENO'
			        ,exc_unit = '9' -- special for crashes, see sp SRV_GET_REPORT_NAME
				,exc_info = 'CRASH DURING DB SHUTDOWN! ' || trim(coalesce(iif( upper(exc_info) similar to upper('normal:%expired%'), replace(exc_info,'NORMAL:', ''), exc_info ),''))
			where unit = 'sp_halt_on_error'
			order by dts_beg desc
			rows 1
			returning exc_info;
			set list off;
		EOF
	fi
	if [[ $crash_during_run -eq 1 ]]; then
		# Record in perf_log with unit = 'sp_halt_on_error' mostly NOT YET exist at this point
		# because SP sp_halt_on_error was not called for test self-stop.
		# We have to *add* new record into perf_log in order to show it in the final report:
		cat <<- EOF >>$psql
			set list on;
			insert into perf_log(unit, dts_beg, dts_end, stack, exc_unit, exc_info)
			values(
			    'sp_halt_on_error'
			    ,'now'
			    ,'now'
			    ,'script: ${BASH_SOURCE[0]}, line: $LINENO'
			    ,'9' -- special for crashes, see sp SRV_GET_REPORT_NAME
			    ,'CRASH DURING TEST RUN, ' || left(cast(cast('now' as timestamp) as varchar(50)),16)
			)
			returning exc_info;
			set list off;
		EOF
	fi
    # /var/tmp/logs-oltp30/oltp30.report.txt
    $isql_name $dbconn -nod -n -q -pag 9999 -i $psql $dbauth 1>>$rpt 2>&1

    if [[ $conn_as_locksmith -eq 0 ]]; then
        ######################################################
        # 17.05.2020. Cleanup: remove all non-privileged users with names starting with '$mon_usr_prefix':
        ######################################################
        sho "SID=1. Drop temporary non-privileged USERS and ROLE which could be created for reducing affect of mon\$ data gathering." $rpt
	cat <<-EOF >$psql
		rollback;
		set transaction no wait;
		execute procedure srv_drop_oltp_worker;
		commit;
	EOF
        $isql_name $dbconn -nod -q -pag 9999 -i $psql $dbauth 1>>$rpt 2>&1
    fi

    # $tmpdir/oltp30.report.txt -- it DOES contain now some info, we should NOT zap it!
    ####plog=$rpt
    # ---- do NOT ---- rm $plog


    # 22.03.2020: implementing HTML report generation
    #################################################
    phtm=$tmpdir/oltp$fb.report.htm
    rm -f $phtm

    htm_sect="<h3>"
    htm_secc="</h3>"
    htm_repn="<h4>"
    htm_repc="</h4>"
    if [ $make_html -eq 1 ]; then

        echo "<html>">>$phtm
        # ----------------------------
        # INCLUDE STATIC CONTENT: HEAD
        # ----------------------------
        cat $shdir/oltp_report_html_head.inc >>$phtm

	cat <<- EOF >>$phtm
	<body>
	Generated by $shname, ISQL session No. 1 of total launched $winq. $(date +'%d.%m.%Y %H:%M')

	<table>
	    <th>Common</th>
	    <th>Performance</th>
	    <th>Final Results</th>
	    <tr>
	        <td>
	        <ol>
	            $( [[ $gather_hardware_info -eq 1 ]] && echo "<li><a href="#hardwareinfo">Hardware and OS info</a></li>"  )
	            <li><a href="#testsettings">Test configuration</a></li>
	            <li><a href="#testfinishinfo">Test Finish details</a></li>
	            <li><a href="#testworkload">Test workload details</a></li>
	            <li><a href="#qdindexesddl">Indices DDL for heavy-loaded table(s)</a></li>
	        </ol>
	        </td>
	        <td>
	        <ol>
	            <li>Performance, TOTAL score:
	                &nbsp;&nbsp;&nbsp;<span><a href="#perftotal">as table</a><span> &nbsp;&nbsp;&nbsp; <span><a href="#perf_total_chart">as chart</a><span>
	            </li>
	            <!--
	            Disabled 07.05.2020: there is no sense to show average score for some INTERMEDIATE period. Dispersion will beextremely high in this case.
	            Rather, CUMULATIVE value must be used but this is already done in 'Performance per MINUTE' report.
	            <li>Performance in DYNAMIC, $test_intervals intervals:
	                &nbsp;&nbsp;&nbsp;<span><a href="#perfdynam">as table</a><span> &nbsp;&nbsp;&nbsp; <span><a href="#perf_dynamic_chart">as chart</a><span>
	            </li>
	            -->

	            <li>Performance per MINUTE, during test_time phase:
	                &nbsp;&nbsp;&nbsp;<span><a href="#perfminute">as table</a><span> &nbsp;&nbsp;&nbsp; <span><a href="#perf_m1_chart">as chart</a><span>
	            </li>

	            <!-- NOT YET IMPLEMENTED <li><a href="#perftrace">Performance, TRACE data for ISQL #1</a> </li> -->
	            <li><a href="#perfdetail">Performance, DETAILS per units</a> </li>

	EOF

        if [[ $mon_unit_perf -eq 0 ]]; then
	            echo "<li>Monitoring statistics was not gathered. Change config parameter 'mon_unit_perf' to 1 or 2</li>" >>$phtm
        elif [[ $mon_unit_perf -eq 1 ]]; then
                    # query to: SP report_stat_per_units --> table mon_log, group by unit.
                    # table mon_log is fulfilled by SP srv_fill_mon

		cat <<- EOF >>$phtm
	            <li>Monitoring performance: per UNITS
	                &nbsp;&nbsp;&nbsp;<span><a href="#perfmon4unit_table">as table</a><span> &nbsp;&nbsp; <span><a href="#perfmon4unit_chart">as chart</a><span>
	            </li>
	            $( [[ $mon_unit_perf -eq 1 && $fb -ne 25 ]] && echo "<li><a href="#perfmon4tabs">Monitoring performance: per UNITS and TABLES</a></li>" )
		EOF

        elif [[ $mon_unit_perf -eq 2 ]]; then
		cat <<- EOF >>$phtm
	            <li>Memory consumption, metadata cache, attachments activity
	                &nbsp;&nbsp;&nbsp;<span><a href="#perfmon4meta">as table</a><span> &nbsp;&nbsp; <span><a href="#perf_memo_consumption_chart">as chart</a><span>
	            </li>
	            <li>Monitoring data: STATEMENTS activity, <span><a href="#perf_attachments_activity_chart">as chart</a><span>
	            </li>
		EOF
        fi
	# <li><a href=$( [[ $mon_unit_perf -eq 2 ]] && echo "#perfmon4meta" || echo "#perfmetadisabled" )>MON\$-analysis: METADATA cache</a> </li>

	cat <<- EOF >>$phtm
	            <li><a href="#exceptions">Exceptions during test run</a> </li>
	        </ol>
	        </td>
	        <td>
	        <ol>
	            <li><a href="#fbdbinfo">mon\$database and 'show version' results</a> </li>
	EOF
	if [[ $run_db_statistics -eq 0 ]]; then
		echo "<li>Database statistics was not gathered. Change config parameter 'run_db_statistics' to 1.</li>" >>$phtm
	elif [[ $run_db_statistics -lt 0 ]]; then
		echo "<li><a href="#dbstatistics">Database statistics was not gathered: DB is in 'backup lock' state.</a> </li>" >>$phtm
	else
		cat <<- EOF >>$phtm
		    <li><a href="#dbstatistics">Database Statistics, full</a> </li>
		    <li>Record versions statistics
	             &nbsp;&nbsp;&nbsp;<span><a href="#dbvers_table">as table</a><span> &nbsp;&nbsp; <span><a href="#dbvers_chart">as chart</a><span>
	            </li>
		EOF
	fi
	if [[ $run_db_validation -eq 0 ]]; then
		echo "<li>Database validation was not performed. Change config parameter 'run_db_validation' to 1.</li>" >>$phtm
	else
		echo "<li><a href="#dbvalidation">Database Validation Results</a> </li>" >>$phtm
	fi

	cat <<- EOF >>$phtm
	            <li><a href="#fblogcompare">New in firebird.log while test was run</a> </li>
	            <li><a href="#finalpart">Final processing of ISQL logs</a> </li>
	        </ol>
	        </td>
	    </tr>
	</table>


	EOF
    fi
    # make_html=1

    if [ $gather_hardware_info -eq 1 ]; then
	cat <<- EOF >>$plog
	
	######################################################################
	###  g a t h e r     h a r d w a r e    a n d     O S    i n f o   ###
	######################################################################
	
	EOF

        if [ $make_html -eq 1 ]; then
	cat <<- EOF >>$phtm
            $htm_sect <a name="hardwareinfo"> Hardware and OS info </a> $htm_secc
            <table>
	EOF
        fi

        run_cmd="hostnamectl"
        apply_cmd "$run_cmd" "host_info" $tmpauxlog 1
        cat $tmpauxlog >>$plog

        # 23.03.20 00:15:15. Command: 'hostnamectl'
        # Static hostname: foo.company.com
        #       Icon name: computer-server
        #         Chassis: server
        #      Machine ID: aee...e77
        #         Boot ID: 36f...58d
        #Operating System: CentOS Linux 7 (Core)
        #     CPE OS Name: cpe:/o:centos:centos:7
        #          Kernel: Linux 3.10.0-957.5.1.el7.x86_64
        #    Architecture: x86-64

        if [ $make_html -eq 1 ]; then
            echo "<tr><th colspan=2>Command: $run_cmd</th></tr>" >> $phtm
            while read line; do
                echo "<tr><td>$(echo "$line" | cut -d : -f2)</td><td>$(echo "$line" | cut -d : -f3-)</td></tr>" >>$phtm
            done < <( grep . $tmpauxlog | tail --lines=+2 )
        fi

        # --++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--+

        run_cmd="who -b"
        apply_cmd "$run_cmd" "bootup_info" $tmpauxlog 1
        cat $tmpauxlog >>$plog
        # bootup_info: system boot 2019-11-01 09:39

        if [ $make_html -eq 1 ]; then
	cat <<- EOF >>$phtm
	    <tr><th colspan=2>Command: $run_cmd</th></tr>
	EOF

          while read line; do
            echo "<tr><td>$(echo "$line" | cut -d : -f1)</td><td>$(echo "$line" | cut -d : -f2-)</td></tr>" >>$phtm
          done < <( grep . $tmpauxlog | tail --lines=+2  )
        fi

        # --++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--+

        run_cmd="dmidecode -t system|grep -i -e 'manufacturer\|product\|hypervisor'"
        apply_cmd "$run_cmd" "mboard_info" $tmpauxlog 1
        cat $tmpauxlog >>$plog

        # mboard_info: Manufacturer: HP
        # mboard_info: Product Name: ProLiant DL380 Gen9

        if [ $make_html -eq 1 ]; then
	cat <<- EOF >>$phtm
	    <tr><th colspan=2>Command: $run_cmd</th></tr>
	EOF
          while read line; do
            echo "<tr><td>$(echo "$line" | cut -d : -f2)</td><td>$(echo "$line" | cut -d : -f3-)</td></tr>" >>$phtm
          done < <( grep . $tmpauxlog | tail --lines=+2 )
        fi


        # --++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--+

        run_cmd="dmesg | grep DMI"
        apply_cmd "$run_cmd" "DMI_info" $tmpauxlog 1
        cat $tmpauxlog >>$plog
        if [ $make_html -eq 1 ]; then
	cat <<- EOF >>$phtm
	    <tr><th colspan=2>Command: $run_cmd</th></tr>
	EOF
          while read line; do
            echo "<tr><td>$(echo "$line" | cut -d : -f2)</td><td>$(echo "$line" | cut -d : -f3-)</td></tr>" >>$phtm
          done < <( grep . $tmpauxlog | tail --lines=+2 )
        fi

        # --++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--+

        run_cmd="lscpu | grep -i -v flags"
        apply_cmd "$run_cmd" "CPU_info" $tmpauxlog 1
        cat $tmpauxlog >>$plog
        if [ $make_html -eq 1 ]; then
	cat <<- EOF >>$phtm
	    <tr><th colspan=2>Command: $run_cmd</th></tr>
	EOF
          while read line; do
            echo "<tr><td>$(echo "$line" | cut -d : -f2)</td><td>$(echo "$line" | cut -d : -f3-)</td></tr>" >>$phtm
          done < <( grep . $tmpauxlog | tail --lines=+2 )
	fi

        # --++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--+

        run_cmd="cat /proc/meminfo | grep -i -e 'memtotal\|memfree\|memavail\|buffers\|cached\|swapcached'"
        apply_cmd "$run_cmd" "mem_info" $tmpauxlog 1
        cat $tmpauxlog >>$plog

        if [ $make_html -eq 1 ]; then
	cat <<- EOF >>$phtm
	    <tr><th colspan=2>Command: $run_cmd</th></tr>
	EOF
          while read line; do
            echo "<tr><td>$(echo "$line" | cut -d : -f2)</td><td>$(echo "$line" | cut -d : -f3-)</td></tr>" >>$phtm
          done < <( grep . $tmpauxlog | tail --lines=+2 )
	fi


        # --++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--++--+

        run_cmd="fdisk -l"
        apply_cmd "$run_cmd" "fdisk_info" $tmpauxlog 1
        cat $tmpauxlog >>$plog

        # NB: output of fdisk command  contain asterisk. If line with '*' will be echoed then all files from
        # current folder will be substituted instead of this '*'. In order to avoid this one need to enclose
        # into double quotes name of such variable, i.e.: "$line" but not $line 
        # See: https://stackoverflow.com/questions/102049/how-do-i-escape-the-wildcard-asterisk-character-in-bash
        # Example:
        # Disk /dev/sda: 599.9 GB, 599932581888 bytes, 1171743324 sectors
        # Units = sectors of 1 * 512 = 512 bytes
        # Sector size (logical/physical): 512 bytes / 512 bytes
        # I/O size (minimum/optimal): 262144 bytes / 524288 bytes
        if [ $make_html -eq 1 ]; then
	cat <<- EOF >>$phtm
	    <tr><th colspan=2>Command: $run_cmd</th></tr>
	EOF
          while read line; do
            #echo "<tr><td>$(echo "$line" | cut -d : -f2-)</td></tr>" >>$phtm
            echo "<tr><td colspan=2>$(echo "$line")</td></tr>" >>$phtm
          done < <( grep . $tmpauxlog | tail --lines=+2 | cut -d : -f2- | sed '/^ $/d' )
          echo "</table>" >> $phtm
	fi

    else
	rm -f $tmpauxlog
	cat <<- EOF >>$tmpauxlog
		
		Config parameter gather_hardware_info=0, hardware and OS info were NOT gathered.
		===============================================================================
	EOF
	cat $tmpauxlog>>$plog
	if [[ $make_html -eq 1 ]]; then
		echo "$htm_sect <a name="hardwareinfo"> Hardware and OS info </a> $htm_secc" >>$phtm
		add_html_text $tmpauxlog $phtm 0 "null" "pre"
	fi

    fi
    # end of $gather_hardware_info = 1 | 0

#\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

    rpt_name="Server and database settinfs"
    rm -f $tmpauxlog
	cat <<- EOF >>$plog
		
		$rpt_name
		=======================
	EOF
    #run_get_fb_ver% 1>%tmp_file% 2>&1
    #call :add_html_text tmp_file htm_file
    #del %tmp_file% 2>nul
	cat <<- EOF >$psql
            set list on;
            select
                 p.fb_arch as server_mode
                 ,mon\$database_name as db_name
                 ,iif(mon\$forced_writes=0, '$css' || '$warning$OFF', 'ON') as forced_writes
                 ,mon\$sweep_interval as sweep_int
                 ,mon\$page_buffers as page_buffers
                 ,mon\$page_size as page_size
            from mon\$database
            left join sys_get_fb_arch('$usr', '$pwd') p on 1=1;
	EOF
    $isql_name $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>$tmpauxlog 2>&1
    cat $tmpauxlog >>$plog
    if [[ $make_html -eq 1 ]]; then
	cat <<- EOF >>$phtm
	    $htm_sect <a name="testsettings">$rpt_name</a> $htm_secc
	EOF
	add_html_text $tmpauxlog $phtm 0 "null" "pre"
    fi

    rpt_name="Test configuration settings"
	cat <<- EOF >>$plog
		
		$rpt_name
		=======================
	EOF

    rm -f $tmpauxlog
    while IFS='=' read lhs rhs
    do
        if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
	  lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
          rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
          [[ ${rhs:0:1} == "$" ]] && rhs=$(eval "echo $rhs")
	  echo "param=$lhs, val=$rhs" >> $tmpauxlog
        fi
    done < <(awk '$1=$1' $cfg  | grep "^[^#]" | sort)
    #( sed -e 's/^[ \t]*//' $cfg | grep "^[^#;]" | sort)

    if [[ -z "$clu" ]]; then
	echo Name of of interactive SQL utility: 'isql' >>$tmpauxlog
    else
	# Name of ISQL on Ubuntu/Debian when FB is installed from OS repository
	# 'isql-fb' etc:
	echo Custom name of interactive SQL utility: parameter: \'clu\', value: \|$clu\| >>$tmpauxlog
    fi
    cat $tmpauxlog>>$plog

    if [[ $make_html -eq 1 ]]; then
	cat <<- EOF >>$phtm
	    $htm_sect Test configuration settings $htm_secc
	EOF
	add_html_text $tmpauxlog $phtm 0 "null" "pre"
    fi

    #/////////////////////////////////////////////////////////////////////////

	cat <<- EOF >>$plog
	
	################################################################################################
	###  h o w     t e s t    h a s      f i n i s h e d ?   (normally / premature termination)  ###
	################################################################################################
	EOF

	cat <<- "EOF" >$psql
		commit;
		create or alter view v_tmp4rep as
		select
		   p.exc_info as finish_state, p.dts_end, p.fb_gdscode, e.fb_mnemona,
		      coalesce(p.stack,'') as stack,
		         p.ip,p.trn_id, p.att_id,p.exc_unit
		from rdb$database r
		left join perf_log p on p.unit = 'sp_halt_on_error' -- 13.10.2018: do NOT replace here "perf_log" (table) with "v_perf_log" (view)
		left join fb_errors e on p.fb_gdscode = e.fb_gdscode
		order by p.dts_beg desc
		rows 1;
		commit;
		-----------------------------------------------------
		set list on;
		select
		    x.finish_state
		   ,x.dts_end
		   ,x.fb_gdscode
		   ,x.fb_mnemona
		   ,x.stack
		   ,x.ip
		   ,x.trn_id
		   ,x.att_id
		   ,x.exc_unit
		from v_tmp4rep x
		;
		set list off;
	EOF

    $isql_name $dbconn -now -q -pag 9999 -i $psql $dbauth 1>$tmpauxlog 2>&1
    cat $tmpauxlog>>$plog

    # psql = /var/tmp/logs.oltp30/oltp30_localhost.localdomain-001.performance_report.tmp

    if [[ $make_html -eq 1 ]]; then
	cat <<- EOF >>$phtm
            $htm_sect <a name="testfinishinfo"> Test finish info </a> $htm_secc
	EOF
	cat <<- "EOF" >$psql
	    set list on;
            select
               iif( x.finish_state containing 'abnormal' or x.finish_state containing 'crash'
                    ,'$css' || '$error$' -- split style because its name is searched in html parsing routines and will be cuted off otherwise
                    ,iif( x.finish_state containing 'premature'
                         ,'$css' || '$warning$' -- split style because its name is searched in html parsing routines and will be cuted off otherwise
                         ,'$css' || '$success$' -- split style because its name is searched in html parsing routines and will be cuted off otherwise
                       )
                   ) || x.finish_state as finish_state
              ,x.dts_end
              ,x.fb_gdscode
              ,x.fb_mnemona
              ,x.stack
              ,x.ip 
              ,x.trn_id 
              ,x.att_id 
              ,x.exc_unit
           from v_tmp4rep x
           ;
	EOF
        $isql_name $dbconn -now -q -pag 9999 -i $psql $dbauth 1>$tmpauxlog 2>&1

        #add_html_table $psql $phtm
        add_html_text $tmpauxlog $phtm 0 "null" "pre"
    fi

    #------------------------------------------------------------------------

	cat <<- EOF >>$plog

	#####################################################
	###  c u r r e n t    t e s t    s e t t i n g s  ###
	#####################################################
	EOF
	
	rpt_name="Test workload details"
	cat <<- "EOF" >$psql
	    set width working_mode 12;
	    set width setting 32;
	    set width val 30;
	    --set list on;
	    select 'WORKING_MODE' as setting_name, s.svalue as setting_value
	    from settings s
	    where s.working_mode = 'INIT' and s.mcode='WORKING_MODE'
	    UNION ALL
	    select s.mcode as setting, s.svalue as val
	    from settings s
	    join (
	        select s.svalue as working_mode
	        from settings s
	        where s.working_mode = 'INIT' and s.mcode='WORKING_MODE'
	         ) w on s.working_mode = w.working_mode;
	EOF
        $isql_name $dbconn -now -q -pag 9999 -i $psql $dbauth 1>>$plog 2>&1

	if [[ $make_html -eq 1 ]]; then
		cat <<- EOF >>$phtm
		    $htm_sect <a name="testworkload"> $rpt_name </a> $htm_secc
		EOF
		add_html_table $psql $phtm
		#add_html_text $tmpauxlog $phtm 0 "null" "pre"
	fi
	rm -f $psql

	#-----------------------------------------------------------------------

	rpt_name="Indexes for heavy-loaded tables"
	cat <<- "EOF" >$psql
	    set width tab_name 13;
	    set width idx_name 31;
	    set width idx_key 45;
	    select * from z_qd_indices_ddl;
	EOF
	
	cat <<- EOF >>$plog
		
		$rpt_name
		===============================
	EOF
        $isql_name $dbconn -now -q -pag 9999 -i $psql $dbauth 1>>$plog 2>&1

	if [[ $make_html -eq 1 ]]; then
		cat <<- EOF >>$phtm
		    $htm_sect <a name="qdindexesddl"> $rpt_name </a> $htm_secc
		EOF
		add_html_table $psql $phtm
	fi
	rm -f $psql

	#-----------------------------------------------------------------------

    sho "SID=$sid. Start script aggregation performance data." $plog
	cat <<- "EOF" >$psql
		commit;
		set transaction no wait;
		set list on;
		select
		    'Final data aggregation from PERF_FPLIT_nn tables to PERF_AGG' as msg
		    ,p.msg as result
		from srv_aggregate_perf_data( 1 ) as p; -- 1 = ignore stop-flag, do aggregation anyway.
		commit;
		set list off;
	EOF
    $isql_name $dbconn -now -q -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
    # MSG                             Final data aggregation from PERF_FPLIT_nn tables to PERF_AGG
    # RESULT                          i=123451, u=32154, ms=12387

    sho "SID=$sid. Finish script aggregation performance data." $plog
    # todo later: srv_gen_sql_4drop_perf_split -- see oltp_adjust_DDL.sql 

    rm -f $psql $tmpauxtmp $tmpauxsql $tmpauxerr

	cat <<- EOF >>$plog
	###################################################
	###   p e r f o r m a n c e     r e p o r t s   ###
	###################################################
	EOF

	#--------------------------------------------------------------------
	
	rpt_name="Performance in TOTAL"
	cat <<- EOF >>$plog
		
		$rpt_name
		=====================
		Get overall performance report for last test_time=$test_time minutes of activity.
		Value in column "avg_times_per_minute" in 1st row is OVERALL PERFORMANCE INDEX.
	EOF
	
	cat <<- "EOF" >>$psql
		set width action 35;
		select
		   business_action as action
		   ,avg_times_per_minute
		   ,avg_elapsed_ms
		   ,successful_times_done
		from rdb$database
		left join report_perf_total on 1=1;
		commit;
	EOF
	
	cat $psql >> $plog

    s1=$(date +%s)
    $isql_name $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
    # Add timestamps of start and finish and how long last ISQL was:
    log_elapsed_time $s1 $plog "$rpt_name"


    if [[ $make_html -eq 1 ]]; then
	# 04.05.2020: show chart using google charts api.
	cat <<-EOF >$tmpcharts
		draw_func_name=perf_total_chart
		href_name=perf_total_chart
		href_title=Performance in TOTAL, chart
		x_axis_field=action
		y_fields_list=successful_times_done;    
		y_format_list=pattern:'0';
		x_values_skip_pattern=OVERALL
		chart_type=PieChart
		chart_div_wid=1100
		chart_div_hei=700
	EOF

        echo "$htm_sect <a name="perftotal"> $rpt_name </a> $htm_secc" >> $phtm
	s1=$(date +%s)
	add_html_table $psql $phtm $tmpcharts
	#                 1    2        3
	log_elapsed_time $s1 $phtm "$rpt_name"
    fi
    rm -f $psql

#stop here 08.05.2020 1918, todo: fix this:
#,['*** OVERALL *** for 5 minutes:' ]
#,['customer order: creation' ]
#,['customer order: refuse' ]
#,['order to supplier: creation' ]

    #------------------------------------------------------------------------------------
    if [[ 1 -eq 0 ]]; then
        ##############################################
        ### ::: NB ::: FOLLOWING CODE WAS DISABLED ###
        ##############################################
        rpt_name="Performance in DYNAMIC"
	cat <<- EOF >>$plog
		
		$rpt_name
		=======================
	EOF
	
	cat <<- "EOF" >$psql
	    -- Get performance score for N equal time intervals, where N is defined by value 'test_intervals' config parameter
		set width itrv_no  7;
		set width itrv_beg 8;
		set width itrv_end 8;
		select cast(interval_no as smallint) as itrv_no
		      ,cnt_ok_per_minute
		      ,cnt_all
		      ,cnt_ok
		      ,cnt_err
		      ,cast(err_prc as numeric(8,2)) as err_prc
		      ,substring(cast(interval_beg as varchar(24)) from 12 for 8) itrv_beg
		      ,substring(cast(interval_end as varchar(24)) from 12 for 8) itrv_end
		from rdb$database
		left join report_perf_dynamic p on 1=1
		;
		commit;
	EOF
	cat $psql >> $plog

        s1=$(date +%s)
	$isql_name $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
        # Add timestamps of start and finish and how long last ISQL was:
	log_elapsed_time $s1 $plog "$rpt_name"

        if [ $make_html -eq 1 ]; then
		# 04.05.2020: show chart using google charts api.
		cat <<-EOF >$tmpcharts
			draw_func_name=perf_dynamic_chart
			href_name=perf_dynamic_chart
			href_title=Performance per intervals, chart
			x_axis_field=itrv_no
			y_axis_field=cnt_ok_per_minute
			x_axis_title=interval No.
			y_axis_title=performance
			chart_color=DarkSeaGreen
			axis_color=DarkOliveGreen
			chart_type=LineChart
			curve_type=function
		        chart_div_wid=1300
		EOF
            echo "$htm_sect <a name="perfdynam">$rpt_name</a> $htm_secc" >> $phtm
	    s1=$(date +%s)
	    add_html_table $psql $phtm $tmpcharts
	    #                 1    2        3
	    log_elapsed_time $s1 $phtm "$rpt_name"
	
        fi
	rm -f $psql
    fi
    # end of DISABLED block for performance in dynamic (since 07-05-2020)

    #------------------------------------------------------------------------------------

    rm -f $psql
    rpt_name="Performance for every MINUTE"
	cat <<- EOF >>$plog
		
		$rpt_name
		=============================
		Extract values of ESTIMATED performance that was evaluated after EACH business
		operation finished.
		These data can help to find proper value of config parameter 'warm_time'.
		Current value of config parameter 'warm_time' = $warm_time.
	EOF

	cat <<- EOF >>$psql
        set width test_phase 20;
        select
            test_phase_name
            ,minutes_passed
            ,perf_score
            -- disabled: this is NOT a number of active attachments >>> ,distinct_workers
        from report_perf_per_minute
        where test_phase_name = 'TEST_TIME' -- remove 'WARM_TIME' phase in order to draw ONE line in chart
        ;
        commit;
	EOF

    cat $psql >> $plog
    s1=$(date +%s)
    $isql_name $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
    # Add timestamps of start and finish and how long last ISQL was:
    log_elapsed_time $s1 $plog "$rpt_name"
    if [ $make_html -eq 1 ]; then
	cat <<-EOF >$tmpcharts
		draw_func_name=perf_m1_chart
		href_name=perf_m1_chart
		href_title=Performance per minute, chart
		axis_color=DarkBlue
		x_axis_field=minutes_passed
		x_axis_title=minute
		y_fields_list=perf_score
		y_format_list=pattern:'0'
		y_colors_list=Blue
		y_legends_list=performance: number of successfully completed business actions per minute.
		y_sc__DO__NOT__ale_type=log
		chart_div_wid=1400
		point_size=3
		chart_area_options={ left:60, top:25 }
	EOF

        echo "$htm_sect <a name="perfminute">$rpt_name</a> $htm_secc" >> $phtm
	s1=$(date +%s)
	add_html_table $psql $phtm $tmpcharts
        #                1     2       3
	log_elapsed_time $s1 $phtm "$rpt_name"
    fi
    rm -f $psql

    #------------------------------------------------------------------------------------
    rpt_name="Performance in DETAILS"
	cat <<- EOF >>$plog

		$rpt_name
		=======================
		Get performance report with detaliation per units, for last test_time=$test_time minutes of workload.
		Fields:
		  CNT_ALL = total number of any level actions (business and internal) that were launched,
		  CNT_OK  = total number of any level actions that finished SUCCESSFULLY,
		  OK_MIN_MS, OK_MAX_MS, OK_AVG_MS = min, max and avg time of actions from CNT_OK.
	EOF

	cat <<- "EOF" >$psql
		set width unit 40;
		select
		    unit
		    ,cnt_all
		    ,cnt_ok
		    ,cnt_err
		    ,err_prc
		    ,ok_min_ms
		    ,ok_max_ms
		    ,ok_avg_ms
		    ,cnt_lk_confl
		    ,cnt_user_exc
		from rdb$database
		left join report_perf_detailed on 1=1;
		commit;
	EOF
	cat $psql >> $plog

    s1=$(date +%s)
    $isql_name $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
    # Add timestamps of start and finish and how long last ISQL was:
    log_elapsed_time $s1 $plog "$rpt_name"
    if [ $make_html -eq 1 ]; then
        echo "$htm_sect <a name="perfdetail">$rpt_name</a> $htm_secc" >> $phtm
	s1=$(date +%s)
	add_html_table $psql $phtm
	log_elapsed_time $s1 $phtm "$rpt_name"
    fi
    rm -f $psql

    #------------------------------------------------------------------------------------

    rpt_name="Monitoring data, per application UNITS"
    if [ $mon_unit_perf -eq 1 ]; then

		cat <<- EOF >>$plog

			$rpt_name
			=======================================
			Get report about gathered MONITOR tables data, detalization per UNITS.
			NOTE: source view for this report will be created only when config
			parameter 'mon_unit_perf' has value 1.
		EOF
		cat <<- "EOF" >$psql
			set width unit 31;
			select z.*
			from rdb$database
			left join report_stat_per_units z on 1=1;
			commit;
		EOF
		cat $psql >> $plog

		s1=$(date +%s)
		$isql_name $dbconn -now -q -n -pag 99999 -i $psql $dbauth 1>>$plog 2>&1
		# Add timestamps of start and finish and how long last ISQL was:
		log_elapsed_time $s1 $plog "$rpt_name"

		if [ $make_html -eq 1 ]; then

			echo "$htm_sect <a name="perfmon4unit_table">$rpt_name - table:</a> $htm_secc" >> $phtm
		        add_html_table $psql $phtm
			
			echo "$htm_sect <a name="perfmon4unit_chart">$rpt_name - charts:</a> $htm_secc" >> $phtm

			# ::::::::::::::::::::::::::::::: 1a:  reads vs fetches ::::::::::::::::::::::::::::::::
			cat <<- "EOF" >$psql
		            set width unit 31;
			    select
			        z.unit
			        ,z.avg_reads
			        ,z.avg_fetches
			    from rdb$database
			    left join report_stat_per_units z on 1=1;
			    commit;
			EOF

			cat <<-EOF >$tmpcharts
			    chart_only_show=1
			    chart_type=ColumnChart
			    chart_title=Performance: reads and fetches, average
			    chart_inline_block=1
			    draw_func_name=mon_reads_fetches_chart
			    href_name=mon_reads_fetches_chart
			    axis_color=DarkBlue
			    x_axis_field=unit
			    x_axis_title=action
			    y_fields_list=avg_reads;      avg_fetches
			    y_format_list=pattern:'0.00'; pattern:'0.00'
			    y_colors_list=Teal;           DeepSkyBlue
			    y_legends_list=Average reads; Average fetches
			    y_scale_type=log
			    chart_div_wid=550
			    chart_area_options={ left:90, right:5, width:"100%" }
			    point_size=3
			EOF
			add_html_table $psql $phtm $tmpcharts
		        #                1     2       3
			###log_elapsed_time $s1 $phtm "$rpt_name"


			# ::::::::::::::::::::::::::::: 1b: writes vs marks :::::::::::::::::::::::::::::::
			cat <<- "EOF" >$psql
		            set width unit 31;
			    select
			        z.unit
			        ,z.avg_writes
			        ,z.avg_marks
			    from rdb$database
			    left join report_stat_per_units z on 1=1;
			    commit;
			EOF

			cat <<-EOF >$tmpcharts
			    chart_only_show=1
			    chart_type=ColumnChart
			    chart_title=Performance: writes and marks, average
			    chart_inline_block=1
			    draw_func_name=mon_writes_marks_chart
			    href_name=mon_writes_marks_chart
			    axis_color=DarkBlue
			    x_axis_field=unit
			    x_axis_title=action
			    y_fields_list=avg_writes;      avg_marks
			    y_format_list=pattern:'0.00';  pattern:'0.00'
			    y_colors_list=DarkMagenta;     HotPink
			    y_legends_list=Average writes; Average marks
			    y_scale_type=log
			    chart_div_wid=550
			    chart_area_options={ left:90, right:5, width:"100%" }
			    point_size=3
			EOF
			add_html_table $psql $phtm $tmpcharts
		        #                1     2       3
			###log_elapsed_time $s1 $phtm "$rpt_name"

			#...................
			echo "<br>" >> $phtm
			#...................


			# :::::::::::::::::::::::::: 2a: page cache usage  :::::::::::::::::::::::
			cat <<- "EOF" >$psql
		            set width unit 31;
			    select
			        z.unit
			        ,1.0000*(z.avg_reads / z.avg_fetches) as "reads / fetches"
			        ,1.0000*(z.avg_writes / z.avg_marks) as "writes / marks"
			    from rdb$database
			    left join report_stat_per_units z on 1=1;
			    commit;
			EOF

			cat <<-EOF >$tmpcharts
			    chart_only_show=1
			    chart_type=ColumnChart
			    chart_title=Performance: avg. ratio of page cache misses (0: good, 1: poor)
			    chart_inline_block=1
			    draw_func_name=mon_page_cache_usage_chart
			    href_name=mon_page_cache_usage_chart
			    axis_color=DarkBlue
			    x_axis_field=unit
			    x_axis_title=action
			    y_fields_list=reads / fetches;           writes / marks
			    y_format_list=pattern:'0.0000';          pattern:'0.0000'
			    y_colors_list=DarkCyan;                  DarkOrchid
			    y_legends_list=Average reads/fetches;    Average writes/marks
			    y_scale___DO_NOT__type=log
			    chart_div_wid=550
			    chart_area_options={ left:90, right:5, width:"100%" }
			    point_size=3
			EOF
			add_html_table $psql $phtm $tmpcharts
		        #                1     2       3
			###log_elapsed_time $s1 $phtm "$rpt_name"

			# :::::::::::::::::::::::::: 2b: memory usage  :::::::::::::::::::::::
			cat <<- "EOF" >$psql
			    -- ATTENTION: counters in the MON$MEMORY_USAGE are *not* cumulative,
			    -- their values are like 'snapshots' and represent current memory consumption.
			    -- Delta between start and end of some query has no sense, we have to get only
			    -- value that was gathered at the FINAL of business action (i.e. after it ended but before commit).
			    -- See SP SRV_FILL_MON: we take in account only values that was at the END of action and ignore
			    -- starting values (with t.mult=-1): select ... max( nullif(t.mult,-1) * t.mem_...) ...
		            set width unit 31;
			    select
			        z.unit
			        ,z.avg_mem_used
			        ,z.avg_mem_alloc
			    from rdb$database
			    left join report_stat_per_units z on 1=1;
			    commit;
			EOF

			cat <<-EOF >$tmpcharts
			    chart_only_show=1
			    chart_type=ColumnChart
			    chart_title=OS memory consumption, average at the end of each business action
			    chart_inline_block=1
			    draw_func_name=mon_os_memory_usage_chart
			    href_name=mon_os_memory_usage_chart
			    axis_color=DarkBlue
			    x_axis_field=unit
			    x_axis_title=action
			    y_fields_list=avg_mem_used;              avg_mem_alloc
			    y_format_list=pattern:'0';               pattern:'0'
			    y_colors_list=RosyBrown;                 DarkOrange
			    y_legends_list=Avg memory_used;          Avg memory_allocated
			    y_scale___DO_NOT__type=log
			    chart_div_wid=550
			    chart_area_options={ left:120, right:5, width:"100%" }
			    point_size=3
			EOF
			add_html_table $psql $phtm $tmpcharts
		        #                1     2       3
			###log_elapsed_time $s1 $phtm "$rpt_name"

			#...................
			echo "<br>" >> $phtm
			#...................

			# :::::::::::::::::  3a: scans, absolute values: sequential and indexed  :::::::::::::::::
			cat <<- "EOF" >$psql
		            set width unit 31;
			    select
			        z.unit
			        ,z.avg_seq
			        ,z.avg_idx
			    from rdb$database
			    left join report_stat_per_units z on 1=1;
			    commit;
			EOF

			cat <<-EOF >$tmpcharts
			    chart_only_show=1
			    chart_type=ColumnChart
			    chart_title=Performance: sequential and indexed scans, average
			    chart_inline_block=1
			    draw_func_name=mon_seq_idx_chart
			    href_name=mon_seq_idx_chart
			    axis_color=DarkBlue
			    x_axis_field=unit
			    x_axis_title=action
			    y_fields_list=avg_seq;         avg_idx
			    y_format_list=pattern:'0.00';  pattern:'0.00'
			    y_colors_list=DarkRed;         DarkCyan
			    y_legends_list=Average sequential reads; Average indexed reads
			    y_scale_type=log
			    chart_div_wid=550
			    chart_area_options={ left:90, right:5, width:"100%" }
			    point_size=3
			EOF
			add_html_table $psql $phtm $tmpcharts
		        #                1     2       3
			###log_elapsed_time $s1 $phtm "$rpt_name"


			# ::::::  3b: scans, absolute values: repeatable, backvers. and fragmented records ::::::::
			cat <<- "EOF" >$psql
		            set width unit 31;
			    select
			        z.unit
			        ,avg_rpt -- monrecord_stats.monrecord_rpt_reads
			        ,avg_bkv -- monrecord_stats.monbackversion_reads -- since rev. 60012, 28.08.2014 19:16
			        ,avg_frg -- monrecord_stats.monfragment_reads
			    from rdb$database
			    left join report_stat_per_units z on 1=1;
			    commit;
			EOF

			cat <<-EOF >$tmpcharts
			    chart_only_show=1
			    chart_type=ColumnChart
			    chart_title=Avg number of: repeatable, back version and fragmented record scans
			    chart_inline_block=1
			    draw_func_name=mon_rbf_chart
			    href_name=mon_rbf_chart
			    axis_color=DarkBlue
			    x_axis_field=unit
			    x_axis_title=action
			    y_fields_list=avg_rpt;         avg_bkv;           avg_frg
			    y_format_list=pattern:'0.00';  pattern:'0.00';    pattern:'0.00'
			    y_colors_list=BlueViolet;      DarkGoldenRod;     Silver
			    y_legends_list=Avg. repeatable scans; Avg. back versions scans; Avg. fragmented scans
			    y_scale_type=log
			    chart_div_wid=550
			    chart_area_options={ left:90, right:5, width:"100%" }
			    point_size=3
			EOF
			add_html_table $psql $phtm $tmpcharts
		        #                1     2       3
			###log_elapsed_time $s1 $phtm "$rpt_name"

			#...................
			echo "<br>" >> $phtm
			#...................

			# :::::::::::::::::::::::::  4a:  scans, ratios  :::::::::::::::::::::::::::
			cat <<- "EOF" >$psql
		            set width unit 31;
			    select
			        z.unit
			        ,avg_bkv_per_rec -- numeric(12,4); see: mon_log.bkv_per_seq_idx_rpt, computed by: bkv_reads / (rec_seq_reads + rec_idx_reads + rec_rpt_reads)
			        ,avg_frg_per_rec -- numeric(12,4); see: mon_log.frg_per_seq_idx_rpt, computed by: frg_reads / (rec_seq_reads + rec_idx_reads + rec_rpt_reads)
			    from rdb$database
			    left join report_stat_per_units z on 1=1;
			    commit;
			EOF

			cat <<-EOF >$tmpcharts
			    chart_only_show=1
			    chart_type=ColumnChart
			    chart_title=Avg. ratio of: 1) back_vers_scans / total_scans,  2) fragmented_record_scans / total_scans
			    chart_inline_block=1
			    draw_func_name=mon_bkv_frg_ratio_chart
			    href_name=mon_rbf_chart
			    axis_color=DarkBlue
			    x_axis_field=unit
			    x_axis_title=action
			    y_fields_list=avg_bkv_per_rec;  avg_frg_per_rec
			    y_format_list=pattern:'0.0000'; pattern:'0.0000'
			    y_colors_list=PaleGoldenRod;    Orchid
			    y_legends_list=Avg. back_vers_scans / total_scans; Avg. fragm_rec_scans / total_scans
			    y_scale_type=log
			    chart_div_wid=550
			    chart_area_options={ left:90, right:5, width:"100%" }
			    point_size=3
			EOF
			add_html_table $psql $phtm $tmpcharts
		        #                1     2       3
			###log_elapsed_time $s1 $phtm "$rpt_name"

			# :::::::::::::::::::::::   4b:  modifications   ::::::::::::::::::::::::::::
			cat <<- "EOF" >$psql
		            set width unit 31;
			    select
			        z.unit
			        ,avg_ins
			        ,avg_upd
			        ,avg_del
			    from rdb$database
			    left join report_stat_per_units z on 1=1;
			    commit;
			EOF

			cat <<-EOF >$tmpcharts
			    chart_only_show=1
			    chart_type=ColumnChart
			    chart_title=Avg. number of inserts, updates and deletes
			    chart_inline_block=1
			    draw_func_name=mon_ins_upd_del_chart
			    href_name=mon_iud_chart
			    axis_color=DarkBlue
			    x_axis_field=unit
			    x_axis_title=action
			    y_fields_list=avg_ins;         avg_upd;         avg_del
			    y_format_list=pattern:'0.00';  pattern:'0.00';  pattern: '0.00'
			    y_colors_list=Turquoise;       PeachPuff;       Maroon
			    y_legends_list=Avg. inserts; Avg. updates ; Avg. deletes
			    y_scale_type=log
			    chart_div_wid=550
			    chart_area_options={ left:90, right:5, width:"100%" }
			    point_size=3
			EOF
			add_html_table $psql $phtm $tmpcharts
		        #                1     2       3
			###log_elapsed_time $s1 $phtm "$rpt_name"

			#...................
			echo "<br>" >> $phtm
			#...................


			# ::::::::::::::::::::::::::  5a: garbage-related processing ::::::::::::::::::
			cat <<- "EOF" >$psql
		            set width unit 31;
			    select
			        z.unit
			        ,avg_bko
			        ,avg_pur
			        ,avg_exp
			    from rdb$database
			    left join report_stat_per_units z on 1=1;
			    commit;
			EOF

			cat <<-EOF >$tmpcharts
			    chart_only_show=1
			    chart_type=ColumnChart
			    chart_title=Avg. number of backouts, purges and expunges
			    chart_inline_block=1
			    draw_func_name=mon_bko_pur_exp_chart
			    href_name=mon_bpx_chart
			    axis_color=DarkBlue
			    x_axis_field=unit
			    x_axis_title=action
			    y_fields_list=avg_bko;         avg_pur;         avg_exp
			    y_format_list=pattern:'0.00';  pattern:'0.00';  pattern:'0.00'
			    y_colors_list=Violet;          Coral ;          Gray
			    y_legends_list=Avg. backouts;  Avg. purges ; Avg. expunges
			    y_scale_type=log
			    chart_div_wid=550
			    chart_area_options={ left:90, right:5, width:"100%" }
			    point_size=3
			EOF
			add_html_table $psql $phtm $tmpcharts
		        #                1     2       3
			###log_elapsed_time $s1 $phtm "$rpt_name"


			# ::::::::::::::::::::   5b: record-level lock and conflicts  ::::::::::::::::::
			cat <<- "EOF" >$psql
		            set width unit 31;
			    select
			        z.unit
			        ,z.avg_locks
			        ,z.avg_confl
			    from rdb$database
			    left join report_stat_per_units z on 1=1;
			    commit;
			EOF

			cat <<-EOF >$tmpcharts
			    chart_only_show=1
			    chart_type=ColumnChart
			    chart_title=Performance: record-level locks and conflicts, average
			    chart_inline_block=1
			    draw_func_name=mon_lock_and_conflict_chart
			    href_name=mon_lock_and_conflict_chart
			    axis_color=DarkBlue
			    x_axis_field=unit
			    x_axis_title=action
			    y_fields_list=avg_locks;       avg_confl
			    y_format_list=pattern:'0.00';  pattern:'0.00'
			    y_colors_list=DarkOrange;      Yellow
			    y_legends_list=Average record locks; Average lock-conflicts
			    y_scale_type=log
			    chart_div_wid=550
			    chart_area_options={ left:90, right:5, width:"100%" }
			    point_size=3
			EOF
			add_html_table $psql $phtm $tmpcharts
		        #                1     2       3
			###log_elapsed_time $s1 $phtm "$rpt_name"

			#...................
			echo "<br>" >> $phtm
			#...................

			## DEBUG
			#cat <<-EOF >>$phtm
			#<!-- debug xit -->
			#</body>
			#</html>
			#EOF
			
		fi
		rm -f $psql

		if [ $fb -gt 25 ]; then
			rpt_name="Monitoring data, per TABLES and UNITS (avail. only in FB 3.0)"
			cat <<- EOF >>$plog
				
				$rpt_name
				==============================================================
				Get report about gathered MONITOR tables data, detalization  per TABLES and UNITS.
				NOTE: source view for this report will be created only when config
				parameter 'mon_unit_perf' has value 1. Avaliable only for FB 3.0.
			EOF

			cat <<- "EOF" >$psql
				set width unit 31;
				set width table_name 31;
				select z.*
				from rdb$database
				left join report_stat_per_tables z on 1=1;
				commit;
			EOF

			cat $psql >> $plog
			s1=$(date +%s)
			$isql_name $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
			# Add timestamps of start and finish and how long last ISQL was:
			log_elapsed_time $s1 $plog "$rpt_name"
			if [ $make_html -eq 1 ]; then
			    echo "$htm_sect <a name="perfmon4tabs">$rpt_name</a> $htm_secc" >> $phtm
			    s1=$(date +%s)
			    add_html_table $psql $phtm
			    log_elapsed_time $s1 $phtm "$rpt_name"
			fi
			rm -f $psql

		fi # fb is 30 or higher 

    elif [ $mon_unit_perf -eq 2 ]; then

		rpt_name="Memory consumption, metadata cache, attachments activity"
		cat <<- EOF >>$plog
			
			$rpt_name
			====================================
			Get data about memory consumption, metadata cache, attachments and statements.
			NOTE. Config parameter 'mon_unit_perf' must have value 2 for this report.
		EOF
		#if [ $make_html -eq 1 ]; then
		#    echo "$htm_sect <a name="perfmon4meta">$rpt_name</a> $htm_secc" >> $phtm
		#fi
		
		cat <<- "EOF" >$psql
			set heading off;
			set term ^;
			execute block returns(" " dm_info) as
			begin
			    " " = ascii_char(10) || ( select p.page_cache_info from srv_get_page_cache_info p ) ;
			    suspend;
			end
			^
			set term ;^
		EOF

		rm -f $tmpauxlog
		cat <<- "EOF" >>$tmpauxlog
			Fields:
			  page cache memo used            = page cache total size, bytes:
			  memo used, total                = total of mon$memory_usage.mon$memory_used for database level (mon$stat_group = 0);
			  memo allocated, total           = the same of mon$memory_usage.mon$memory_allocated;
			  metadata cache memo used        = metadata cache, bytes;
			  metadata cache percent of total = ratio: metadata cache / (metadata cache + page cache);
			  total attachments cnt           = total number of attachments, regardless of state;
			  active attachments cnt          = number of attachments with mon$state = 1;
			  running statements cnt          = number of statements that are operating with data from page cache (mon$state = 1);
			  stalled statements cnt          = number of statements that are waiting for client request for fetching ( mon$state = 2);
			  memo used by attachments        = total of mon$memory_usage.mon$memory_used for attachment level (mon$stat_group = 1);
			  memo used by transactions       = the same of transaction level (mon$stat_group = 2);
			  memo used by statements         = the same of statement level (mon$stat_group = 3);
		EOF

		$isql_name $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$tmpauxlog 2>&1
		cat $tmpauxlog >> $plog
		if [[ $make_html -eq 1 ]]; then
			echo "$htm_sect <a name="perfmon4meta">$rpt_name</a> $htm_secc" >> $phtm
			add_html_text $tmpauxlog $phtm 0 "null" "pre"
		fi

		cat <<- "EOF" >$psql
			-- SP report_cache_dynamic -> table mon_cache_memory (filled by: SP srv_fill_mon_cache_memory):
			-- ############################################################################################
			set heading on;
			select
			    substring(measurement_timestamp from 12 for 8) as "measurement_dts" -- 21.04.2019 do NOT use alias with SPACES for the 1st field of resultset!
			    ,measurement_elapsed_ms as "measurement duration ms"
			    ,page_cache_memo_used as "page cache memo used"
			    ,memo_used_all as "memo used, total"
			    ,memo_allo_all as "memo allocated, total"
			    ,metadata_cache_memo_used as "metadata cache"
			    ,metadata_cache_percent_of_total as "metadata cache percent of total"
			    ,total_attachments_cnt as "total attachments cnt"
			    ,active_attachments_cnt as "active attachments cnt"
			    ,running_statements_cnt as "running statements cnt"
			    ,stalled_statements_cnt as "stalled statements cnt"
			    ,memo_used_by_attachments as "memo used by attachments"
			    ,memo_used_by_transactions as "memo used by transactions"
			    ,memo_used_by_statements as "memo used by statements"
			from report_cache_dynamic d;
			commit;
		EOF
		cat $psql >> $plog

		s1=$(date +%s)
		$isql_name $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
		# Add timestamps of start and finish and how long last ISQL was:
		log_elapsed_time $s1 $plog "$rpt_name"
		if [ $make_html -eq 1 ]; then
		    s1=$(date +%s)

		    # 1st chart: total memory consumption for DB level

			cat <<-EOF >$tmpcharts
			    draw_func_name=perf_memo_consumption_chart
			    href_name=perf_memo_consumption_chart
			    href_title=Memory consumption, total, chart
			    axis_color=DarkBlue
			    x_axis_field=measurement_dts
			    x_axis_title=timestamp
			    y_fields_list=memo used, total;          memo allocated, total
			    y_colors_list=Aqua;                      Blue
			    y_legends_list=memory used for DB level; memo allocated for DB level
			    y_format_list=pattern:'0';               pattern:'0'
			    y_list_delimiter=;
			    y_sc__DO_NOT_ale_type=log
			    chart_div_hei=500
			    chart_div_wid=1300
			    point_size=3
			    x_axis_slanted_labels=true
			    chart_area_options={ left:90, top:25 }
			EOF
		    add_html_table $psql $phtm $tmpcharts
		    #                 1     2       3
		    # ------------------------------------


		    # 2nd chart (use the same SQL): metadata cache size and memory consumed by attachments, transactions and statements

			cat <<-EOF >$tmpcharts
			    draw_func_name=perf_metadata_cache_chart
			    chart_only_show=1
			    href_name=perf_metadata_cache_chart
			    href_title=Metadata cache size, chart
			    axis_color=DarkBlue
			    x_axis_field=measurement_dts
			    x_axis_title=timestamp
			    y_fields_list=metadata cache;  memo used by attachments;  memo used by transactions;  memo used by statements
			    y_colors_list=DarkCyan;        Red;                       Green;                      BlueViolet
			    y_legends_listmetadata cache;  memory for attachments;    memory for transactions;    memory for statements
			    y_format_list=pattern:'0';     pattern:'0';               pattern:'0';                pattern:'0'
			    y_list_delimiter=;
			    y_scale_type=log
			    y_leg_maxlines=2
			    chart_div_hei=500
			    chart_div_wid=1300
			    point_size=3
			    x_axis_slanted_labels=true
			    chart_area_options={ left:90, top:25 }
			EOF
		    add_html_table $psql $phtm $tmpcharts
		    #                 1     2       3
		    # ------------------------------------

		    # 3rd chart (use the same SQL): count of attachments, running and stalled statements
			cat <<-EOF >$tmpcharts
			    draw_func_name=perf_attachments_activity_chart
			    chart_only_show=1
			    href_name=perf_attachments_activity_chart
			    href_title=Statements activity, chart
			    axis_color=DarkBlue
			    x_axis_field=measurement_dts
			    x_axis_title=timestamp
			    y_fields_list=total attachments cnt; running statements cnt; stalled statements cnt
			    y_colors_list=Red;                   Green;                  BlueViolet
			    y_legends_list=total attachments count;running statements count;stalled statements count
			    y_list_delimiter=;
			    chart_div_hei=500
			    chart_div_wid=1300
			    point_size=3
			    x_axis_slanted_labels=true
			    chart_area_options={ left:60, top:25 }
			EOF
		    add_html_table $psql $phtm $tmpcharts
		    #                 1     2       3

		    log_elapsed_time $s1 $phtm "$rpt_name"
		fi
		rm -f $psql

    else
		cat <<- EOF >$tmpauxlog
		
			Config parameter mon_unit_perf=0, data from MON$ tables were NOT gathered.
			==========================================================================
		EOF
		cat $tmpauxlog >>$plog
		if [[ $make_html -eq 1 ]]; then
			echo "$htm_sect <a name="perfmon4unit">Monitoring data</a> $htm_secc" >> $phtm
			add_html_text $tmpauxlog $phtm 0 "null" "pre"
		fi
		
    fi # mon_unit_perf = 1 | 0
    
    if [[ $mon_unit_perf -eq 1 ]]; then

		cat <<- EOF >$tmpauxlog
		
			Current value of config parameter mon_unit_perf is $mon_unit_perf
			Metadata cache size can be monitored only when mon_unit_perf=2
			==============================================================
		EOF
		cat $tmpauxlog >>$plog
		if [[ $make_html -eq 1 ]]; then
			echo "$htm_sect <a name="perfmetadisabled">Metadata cache size</a> $htm_secc" >> $phtm
			add_html_text $tmpauxlog $phtm 0 "null" "pre"
		fi

    fi

	rpt_name="Exceptions occured during test was in run"
	rm -f $psql
	cat <<- EOF >>$plog
		
		$rpt_name
		==========================================
	EOF

	cat <<- "EOF" >>$psql
		set width unit 40;
		select fb_mnemona, cnt, unit, fb_gdscode
		from rdb$database
		left join report_exceptions on 1=1;
	EOF

	cat $psql >> $plog
	s1=$(date +%s)
	$isql_name $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
	# Add timestamps of start and finish and how long last ISQL was:
	log_elapsed_time $s1 $plog "$rpt_name"
	if [ $make_html -eq 1 ]; then
	    echo "$htm_sect <a name="exceptions">$rpt_name</a> $htm_secc" >> $phtm
	    s1=$(date +%s)
	    add_html_table $psql $phtm
	    log_elapsed_time $s1 $phtm "$rpt_name"
	fi
	rm -f $psql

    #------------------------------------------------------------------------------------
    rpt_name="Content of mon\$database and FB version"
	cat <<- EOF >>$plog

		$rpt_name
		======================================
	EOF
	cat <<- "EOF" >$psql
		set list on;
		select * from mon$database;
		set list off;
		show version;
	EOF
    $isql_name $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>$tmpauxlog 2>&1
    cat $tmpauxlog >>$plog
    if [[ $make_html -eq 1 ]]; then
		cat <<- EOF >>$phtm
		$htm_sect <a name="fbdbinfo">$rpt_name </a> $htm_secc
		EOF
                add_html_text $tmpauxlog $phtm 0 "null" "pre"
    fi
    rm -f $psql

    #------------------------------------------------------------------------------------


    if [ $run_db_statistics -eq 1 ]; then
	run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth action_db_stats sts_data_pages sts_idx_pages sts_record_versions dbname $dbnm"
	cat <<- EOF >>$plog
		
		Obtain database statistics after test.
		======================================
		Command: $run_fbs
	EOF

	rpt_name="Database statistics"
	msg="SID=$sid. $rpt_name"
	sho "$msg - START." $plog
	s1=$(date +%s)
	$run_fbs 1>$tmpauxlog 2>&1
	cat $tmpauxlog >>$plog
	
	# Add timestamps of start and finish and how long last action was:
	log_elapsed_time $s1 $plog "$rpt_name"
	sho "$msg - FINISH." $plog

        if [[ $make_html -eq 1 ]]; then
                echo "$htm_sect <a name="dbstatistics">$rpt_name </a> $htm_secc" >>$phtm
                add_html_text $tmpauxlog $phtm 0 "null" "pre"
        fi

	rm -f $psql
	grep -i " (\|total records:\|total versions:" $tmpauxlog | grep -v "Index " > $tmpauxtmp
	# Get relation names: grep -E " \([0-9]{3,}\)" tmp_1.aux.log
	while read line; do
	    vers=0
	    if echo $line | grep -q -E " \([0-9]{3,}\)" ; then
	        # INVNT_TURNOVER_LOG (155)
	        tabn=$(echo "$line" | cut -d ' ' -f1)
	    elif [[ "$line" == *" total records: "* ]]; then
	        # Average record length: 33.52, total records: 50
	        #    1      2        3     4      5      6      7
	        recs=$(echo "$line" | cut -d ' ' -f7)
	    elif [[ "$line" == *" total versions: "* ]]; then
	        # Average version length: 2.00, total versions: 123, max versions: 456
	        #    1       2       3      4     5      6       7    7      9      10
	        vers=$(echo "$line" | cut -d ' ' -f7 | cut -d ',' -f1)
	        vmax=$(echo "$line" | cut -d ' ' -f10)
	    fi
	    if [[ $vers -gt 0 ]]; then
	        # NB: 'rowset' is INDEXED field.
	        echo "insert into mon_log_table_stats(id, rowset, table_name, rec_inserts, rec_updates, rec_deletes)" >>$psql
	        echo "values( -gen_id(g_common,1), -current_connection, '$tabn', $recs, $vers, $vmax );" >>$psql
	    fi
	done < <( grep . $tmpauxtmp | sed -e 's/^[ \t]*//' )

	cat <<- "EOF" >> $psql
	    commit;
	    set heading off;
	    select -current_connection from rdb$database; -- this will be saved into script env. variable 'xrowset', see below
	    set heading on;
	    commit;
	EOF

	$isql_name $dbconn -q -pag 9999 -i $psql $dbauth 1>$tmpauxtmp 2>&1

	# Get only non-empty row and remove trailing spaces from it:
	xrowset=$(grep . $tmpauxtmp | sed 's/[[:blank:]]*$//')

	cat <<- EOF >$psql
	    commit;
	    create or alter view v_tmp4rep as
	    select
	        t.table_name
	        ,t.rec_inserts as total_recs
	        ,t.rec_updates as total_vers
	        ,t.rec_deletes as max_versions
	        ,cast( 100.0000 * coalesce( t.rec_updates / nullif(t.rec_inserts,0), 0) as numeric(14,4)) as vers_to_recs_prc -- vers_percent
	        ,cast( 100.0000 * coalesce( t.rec_deletes / nullif(t.rec_updates,0), 0) as numeric(14,4)) as maxv_to_vers_prc
	    from mon_log_table_stats t
	    where
	       t.rowset=$xrowset
	       and (t.rec_inserts > 0 or t.rec_updates > 0)
	    order by t.table_name;
	    commit;
	    set width table_name 31;
	    select * from v_tmp4rep;
	EOF

	#set -x
	$isql_name $dbconn -q -pag 9999 -i $psql ${dbauth} 1>$tmpauxtmp 2>&1
	#set +x
	rpt_name="DB statistics: get values of total records and versions"

	sho "SID=$sid. $rpt_name" $plog
	cat $tmpauxtmp >>$plog

	if [[ $make_html -eq 1 ]]; then

		echo "$htm_sect <a name="dbvers_table">Record versions statistics, table</a> $htm_secc" >>$phtm

		cat <<- "EOF" >$psql
		select
		    -- x.table_name
		    iif(x.vers_to_recs_prc > 500, '$css$error$', iif(x.vers_to_recs_prc > 50, '$css$warning$', '')) || table_name as table_name
		   ,x.total_recs
		   ,x.total_vers
		   ,x.max_versions
		   ,x.vers_to_recs_prc
		   ,x.maxv_to_vers_prc
		from v_tmp4rep x
		;
		EOF
		# call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file
		add_html_table $psql $phtm


                echo "$htm_sect <a name="dbvers_chart"> Record versions statistics, chart</a> $htm_secc" >>$phtm

		cat <<-EOF >$tmpcharts
		    draw_func_name=dbstat_recs_and_vers
		    chart_only_show=1
		    href_name=dbstat_recs_and_vers_chart
		    href_title=Total records and versions, chart
		    axis_color=DarkBlue
		    x_axis_field=table_name
		    x_axis_title=table_name
		    y_scale_type=log
		    y_fields_list=total_recs; total_vers
		    y_colors_list=Green;      BlueViolet
		    y_legends_list=total records; total versions
		    y_list_delimiter=;
		    chart_div_hei=500
		    chart_div_wid=1300
		    point_size=3
		    x_axis_slanted_labels=true
		    chart_area_options={ left:60, top:25 }
		    chart_type=ColumnChart
		EOF
		add_html_table $psql $phtm $tmpcharts
		#                 1     2       3

		cat <<-EOF >$tmpcharts
		    draw_func_name=dbstat_maxvers_vs_total_vers
		    chart_only_show=1
		    href_name=dbstat_maxvers_vs_total_vers
		    href_title=Ratios versions / total_records and max_versions / total_versions
		    axis_color=DarkBlue
		    x_axis_field=table_name
		    x_axis_title=table_name
		    y_scale_type=log
		    y_fields_list=vers_to_recs_prc; maxv_to_vers_prc
		    y_colors_list=Blue;             Red
		    y_legends_list=Ratio versions / total_records, percent; Ratio max_versions / versions, percent
		    y_list_delimiter=;
		    chart_div_hei=500
		    chart_div_wid=1300
		    point_size=3
		    x_axis_slanted_labels=true
		    chart_area_options={ left:60, top:25 }
		    chart_type=ColumnChart
		EOF
		add_html_table $psql $phtm $tmpcharts
		#                 1     2       3

		cat <<- EOF >$psql
		    delete from mon_log_table_stats t
		    where t.rowset=$xrowset
		    ;
		    commit;
		EOF

		$isql_name $dbconn -q -pag 9999 -i $psql ${dbauth} 1>$tmpauxtmp 2>&1

	fi
	rm -f $psql
	rm -f $tmpauxtmp

    else

	rm -f $tmpauxlog
	if [[ $run_db_statistics -lt 0 ]]; then
		cat <<- EOF >>$tmpauxlog
		::: ATTENTION :::

		When DB is in 'backup lock' state then statistics will contain only data from the 'main' DB file
		NO data from .delta wll be included, so gathering of this statistics is USELESS. See CORE-6399.
		If this test as launched from oltp-scheduled.bat then check oltp-scheduled_config.win and replace
		its parameter 'BACKUP_LOCK' to 0.
		
		EOF
	else
		cat <<- EOF >>$tmpauxlog

		Database statistics was not gathered, see config parameter 'run_db_statistics'.
		===============================================================================
		EOF
	fi
	
	cat $tmpauxlog>>$plog
	if [[ $make_html -eq 1 ]]; then
		echo "$htm_sect <a name="dbstatistics">Database statistics </a> $htm_secc" >>$phtm
		add_html_text $tmpauxlog $phtm 0 "null" "pre"
	fi
    fi

    #------------------------------------------------------------------------------------

    if [ $run_db_validation -eq 1 ]; then
		rpt_name="Online validation of database"
		skip_val_list="(AGENTS|BUSINESS_OPS|DOC_STATES|FB_ERRORS|EXT_STOPTEST|SETTINGS|OPTYPES|RULES_FOR_%|PHRASES|TMP\$%|MON%|WARE%|Z_%)"
		run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth action_validate dbname $dbnm val_lock_timeout 1 val_tab_excl $skip_val_list"
		cat <<- EOF >>$plog
			
			$rpt_name
			==============================
			Command: $run_fbs
		EOF
		sho "SID=$sid. $rpt_name - START" $plog
		s1=$(date +%s)
		$run_fbs | grep -i -v "process pointer page" 1>$tmpauxlog 2>&1

		cat $tmpauxlog >>$plog
		#grep -i -v "process pointer page" $tmpauxlog >>$plog
		
		# Add timestamps of start and finish and how long last action was:
		log_elapsed_time $s1 $plog "$rpt_name"
		sho "SID=$sid. $rpt_name - FINISH" $plog
		if [[ $make_html -eq 1 ]]; then
			cat <<- EOF >>$phtm
				$htm_sect <a name="dbvalidation">$rpt_name </a> $htm_secc
			EOF
			add_html_text $tmpauxlog $phtm 0 "null" "pre"
		fi
    else
	rm -f $tmpauxlog
	cat <<- EOF >>$tmpauxlog
		
		Database validation was not performed, see config parameter 'run_db_validation'
		===============================================================================
	EOF
	cat $tmpauxlog>>$plog
	if [[ $make_html -eq 1 ]]; then
		echo "$htm_sect <a name="dbvalidation">Database validation </a> $htm_secc" >>$phtm
		add_html_text $tmpauxlog $phtm 0 "null" "pre"
	fi
    fi

    #------------------------------------------------------------------------------------

    run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth $get_log_switch"
    sho "SID=$sid. Gathering firebird.log after test finished." $plog

    $run_fbs 1>$fblog_end 2>>$plog

	cat <<- EOF >>$plog
		Command: $run_fbs
		Check new firebird.log:
	EOF
	
    ls -l $fblog_end 1>>$plog 2>&1

    rpt_name="Comparison of old and new firebird.log: get messages that appeared during test"
    sho "SID=$sid. $rpt_name" $plog


    rm -f $tmpauxlog
    echo --- start of diff output --- >> $tmpauxlog
    diff --unchanged-line-format="" --new-line-format=":%dn: %L"  $fblog_beg $fblog_end 1>>$tmpauxlog 2>&1
    echo --- end of diff output --- >> $tmpauxlog
    rm -f $fblog_beg $fblog_end
    cat $tmpauxlog >>$plog
    if [[ $make_html -eq 1 ]]; then
	cat <<- EOF >>$phtm
		$htm_sect <a name="fblogcompare">$rpt_name </a> $htm_secc
	EOF
	add_html_text $tmpauxlog $phtm 0 "null" "pre"
    fi

    # ---------------------------------------------------------------------------------
    rpt_name="Final processing ISQL logs in $tmpdir according to config parameter 'remove_isql_logs'"
    sho "SID=$sid. $rpt_name" $plog

    log_ptn=$tmpdir/oltp$(($fb))_**.**
    log_cnt=$(ls $log_ptn | wc -l)

    if [[ $crash_during_run -eq 1 ]]; then
        sho "SID=$sid. NOTE: FB has crashed durin test run. Value of 'remove_isql_logs' is changed to 'never'." $plog
        remove_isql_logs=never
    fi

    case $remove_isql_logs in
        never)
            msg="All $log_cnt logs in $tmpdir are preserved"
        ;;
        always)
            msg="All $log_cnt logs in $tmpdir are removed now regardless of occured errors"
            rm -f $log_ptn
        ;;
        if_no_severe_errors)
            msg="There are $log_cnt logs in $tmpdir that can be removed if no severe errors occured"
        ;;
    esac
    msg="${msg}, see config setting 'remove_isql_logs'"
    sho "SID=$sid. $msg" $plog

	cat <<- EOF > $psql
          -- Checking query:
          set list on;
          select
              x.finished_at,
              x.errors_checking_result
          from z_severe_gds_occured x;
          commit;
	EOF

    if [[ $make_html -eq 1 ]]; then
		cat <<- EOF >$tmpauxlog
		$htm_sect <a name="finalpart">$rpt_name </a> $htm_secc
		$(date +'%d.%m.%y %H:%M:%S'). $msg
		Following values of gdscode are considered as SEVERE:
		            0 Unidentified error in PSQL code: gdscode=0 within WHEN block when exception raised.
		    335544321 'string truncation'. Attempt to assign too long text into string variable.
		    335544347 'not_valid'. Validation error for column.
		    335544349 'no_dup'. Attempt to store duplicate value visible to active transactions.
		    335544558 'check_constraint'. Operation violates CHECK constraint on view or table.
		    335544665 'unique_key_violation'. Violation of PRIMARY or UNIQUE KEY constraint.
		    335544838 'foreign_key_target_doesnt_exist'. Foreign key reference target does not exist.
		    335544839 'foreign_key_references_present'. Foreign key references are present for the record.
		EOF
		add_html_text $tmpauxlog $phtm 0 "null" "pre"
    fi

    $isql_name $dbconn -now -q -pag 9999 -i $psql $dbauth 1>>$plog 2>&1

    # ERRORS_CHECKING_RESULT ='No severe PSQL-related problems occured'  ==> we can DELETE temp logs.
    if [ "$remove_isql_logs" == "always" ]; then
        rm -f $log_ptn
    elif [ "$remove_isql_logs" == "if_no_severe_errors" ]; then
        if grep -q -i "no severe" $plog > /dev/null ; then
            # rm -f /var/tmp/logs-oltp30/oltp30_*.*
            rm -f $log_ptn
        fi
    fi

    if [[ $make_html -eq 1 ]]; then
	cat <<- "EOF" >$psql
              select
                  x.finished_at,
                  trim(iif(x.severe_errors_occured = 1, '$css' || '$error$', '')) || x.errors_checking_result as errors_result
              from z_severe_gds_occured x;
              commit;
	EOF
        add_html_table $psql $phtm
    fi
    rm -f $psql

    #-------------------------------------------------------------------------------
    save_report=0

	if [ -n "$fname" ] ; then
		# fname = 'regular' | 'benchmark' --> name of report file must be GENERATED using performance score and other params.
		cat <<- EOF > $psql
		  -- set heading off; -- FB_ARCH
		  set list on;
		  select
		      report_file
		      ,overall_perf
		      ,fb_arch
		      ,html_doc_title -- 10.05.2020: string for top.document.title = '...'
		  from srv_get_report_name('$fname', '$build', $winq);
		  --------------------------------------------------------------------------------------------
		  select
		      coalesce(p.exc_info,'UNKNOWN') as test_finish_state
		      ,coalesce(p.fb_gdscode, 0) as test_abend_gdscode -- when finish_state is normal then this value will be -1
		  from rdb\$database r
		  left join perf_log p on p.unit = 'sp_halt_on_error' -- 13.10.2018: do NOT replace here "perf_log" (table) with "v_perf_log" (view)
		  order by p.dts_beg desc
		  rows 1;
		EOF
                if [ $conn_pool_support -eq 1 ]; then
		    # ::: NB ::: 17.11.2018
		    # SP srv_get_report_name calls sys_get_fb_arch which uses ES/EDS in order to define FB arch.
		    # When using this in Firebird 2.5 with support of CONNECTIONS POOL then we have to clear
		    # manuall its connection pool, otherwise one EDS connection will remain infinitely.
                    echo -e "ALTER EXTERNAL CONNECTIONS POOL CLEAR ALL;">>$psql
                fi

		echo $(date +'%d.%m.%y %H:%M:%S'). Evaluate new name of final report.
		run_isql="$isql_name $dbconn -i $psql -q -nod -c 256 $dbauth"
		$run_isql 1>$tmpsidlog 2>$tmpsiderr

		# Wrong: one trailing space will be included into varable content:
		# ----- do not --- log_with_params_in_name=`grep -v "^$" $tmpsidlog`
		
		if [ -s $tmpsiderr ]; then
			echo ERROR occured while defining name of final report:
			cat $tmpsiderr
			save_report=0
		else
			save_report=1
			# 20200427_1528_score_08248_bld_33289_ss30__3h04m_100_att_fw__on_repl_0
			log_with_params_in_name=`grep -i "report_file" $tmpsidlog | awk '{print $2}'`
			# score_08248 --> 08248
			overall_perf=`grep -i "overall_perf" $tmpsidlog | awk '{print $2}' | awk -F'_' '{print $2}'`

			#test_finish_state=`grep -i "test_finish_state" $tmpsidlog | awk '{print $2}'`
			# Get all words starting from 2nd and remove all leading spaces:
			# http://www.theunixschool.com/2012/12/howto-remove-leading-trailing-spaces.html
			test_finish_state=`grep -i "test_finish_state" $tmpsidlog | cut -d\  -f2- | awk '$1=$1'`

                        # when finish_state is normal then this value will be -1:
			test_abend_gdscode=`grep -i "test_abend_gdscode" $tmpsidlog | awk '{print $2}'`
			
			# Remove first token, leave all others and remove leading spaces:
			# "HTML_DOC_TITLE                  08519:32136/fb40 fw  on repl 0" --> 08519:32136/fb40 fw  on repl 0
			html_doc_title=`grep -i "html_doc_title" $tmpsidlog  | cut -d' ' -f2- | awk '$1=$1'`

			#log_with_params_in_name=`grep -v "^$" $tmpsidlog | sed 's/[ \t]*$//'`
			# ainfo = input arg to this .sh, optional: file_name_this_host_info: 'cpu_2x4_ram_16' etc
			if [ -n "$ainfo" ]; then
			  # Suffix for adding at the end of report name: host location, hardware specific
			  # FB instance info etc (useful when analyze lot of logs).
			  # Make config parameter 'file_name_with_test_params\ commented if this is not needed.
			  log_with_params_in_name=${log_with_params_in_name}_$ainfo
			fi
			log_with_params_in_name=$tmpdir/$log_with_params_in_name.txt
			echo File with report:
			echo $log_with_params_in_name
			rm -f $log_with_params_in_name $psql $tmpsidlog $tmpsiderr
			#######################################################################################
			###  R E N A M E    T E X T    R E P O R T     T O    T H E    F I N A L    N A M E ###
			#######################################################################################
			mv $plog $log_with_params_in_name
			plog=$log_with_params_in_name

		fi
	else
		cat <<- EOF > $tmpauxtmp
			New report has been saved with the same name as old one thus overwriting it.
			You have to change config parameter 'file_name_with_test_params' to 'regular' or 'benchmark'
			if every new report should be saved to new name. In that case final report file will contain
			info about current FB, DB and test settings.
		EOF
		cat $tmpauxtmp
		cat $tmpauxtmp>>$plog
	fi

        msg="End of report."
        sho "$msg" $plog

        rm -f $tmpauxlog
        echo $(date +'%d.%m.%y %H:%M:%S'). $msg > $tmpauxlog
        if [[ $make_html -eq 1 ]]; then

            add_html_text $tmpauxlog $phtm

            if [[ -n "${html_doc_title}" ]]; then
		cat <<- EOF >>$phtm
		<script>
		    // extract main data from full report name for display in the browser tab:
		    top.document.title = '${html_doc_title}';
		</script>
		EOF
            fi
		cat <<- EOF >>$phtm

			</body>
			</html>

		EOF

	    if [ -n "$fname" ] ; then
	      htm_with_params_in_name=${log_with_params_in_name%.*}.htm
	      rm -f $htm_with_params_in_name
	      #######################################################################################
	      ###  R E N A M E    .H T M L - R E P O R T     T O    T H E    F I N A L    N A M E ###
	      #######################################################################################
	      mv $phtm $htm_with_params_in_name
	    fi

        fi

        if [[ $save_report -eq 1 && -s "$results_storage_fbk" ]]; then
			# 27.04.2020: obtain values from SETTINGS and write into special DB for storing overall results:
			# oltp_results.fdb, table results_overall
			results_fbk=$results_storage_fbk # from .conf; $(dirname "${dbnm}")/oltp_results.fbk
			results_fdb=$(dirname "$results_storage_fbk")/tmp_oltp_results.fdb.tmp
			rm -f $results_fdb

			run_cmd="$fbc/gbak -v -c -se $host/$port:service_mgr $results_fbk $results_fdb -user ${usr} -pas ${pwd}"
			sho "Saving data of just completed test to database." $plog
			sho "Restore previously saved DB, command:" $plog
			sho "$run_cmd" $plog
			eval "$run_cmd" 1>$tmpsidlog 2>$tmpsiderr
			catch_err $? $plog $tmperr "Check whether database $results_fbk exists."
			#set -x
			#$fbc/gbak -c -se $host/$port:service_mgr $results_fbk $results_fdb -user ${usr} -pas ${pwd} 1>$tmpsidlog 2>$tmpsiderr
			#set +x
			
			cat <<- EOF > $psql
			    set bail on;
			    connect '$host/$port:$results_fdb' user '${usr}' password '${pwd}';
			    -- defined in oltp_results_storage_DDL.sql:
			    execute procedure eds_obtain_last_test_results(
			        '$host/$port:$dbnm' -- oltp_data_db
			        ,'$usr' -- eds_usr
			        ,'$pwd' -- eds_pwd
			        ,$mon_unit_perf -- smallint
			    );
			    commit;
			    set list on;
			    set echo on;
			    select * from results_overall order by run_id desc rows 1;
			EOF
			
			run_cmd="$isql_name -i $psql -q -nod $dbauth"
			sho "Saving test settings and last run results in $results_fdb. Command:" $plog
			sho "$run_cmd" $plog
			eval "$run_cmd" 1>$tmpsidlog 2>$tmpsiderr
			catch_err $? $plog $tmpsiderr "Check whether database $results_fbk exists."
			cat $tmpsidlog
			cat $tmpsidlog>>$plog

			rm -f  $psql

			if [[ -s "$htm_with_params_in_name" ]]; then
				# disabled 14.09.2020 v_run_id=`echo "set heading off; select run_id from results_overall order by run_id desc rows 1;" | $isql_name -q -nod $host/$port:$results_fdb $dbauth | grep .`
				cat <<- EOF > $psql
					set heading off;
					select run_id from results_overall order by run_id desc rows 1;
				EOF
				run_cmd="$isql_name -i $psql -q -nod $dbauth $host/$port:$results_fdb"
				sho "Obtain last run_id from results_overall table in DB $results_fdb. Command:" $plog
				sho "$run_cmd" $plog
				eval "$run_cmd" 1>$tmpsidlog 2>$tmpsiderr
				catch_err $? $plog $tmpsiderr "Check whether database $results_fdb or table exists."
				# Filter out empty lines and remove all spaces from run_id value:
				v_run_id=$(grep . $tmpsidlog | tr -d "[:blank:]")
				sho "Result: v_run_id=.$v_run_id." $plog
				rm -f $psql $tmpsidlog $tmpsiderr
				#v_run_id="$(echo -e "${v_run_id}" | tr -d '[:space:]')"
				if [[ -n "${v_run_id}" ]]; then
					cat <<-EOF >>$psql
					set bail on;
					set echo on;
					EOF
					zip_cmd=UNSUPPORTED
					if [[ -n "${report_compress_cmd}" ]]; then
					    # 28.06.2020. Compress to stdout and redirect to base64 text:
					    # 10 digits, 26 lowercase characters, 26 uppercase characters as well as the Plus sign (+) and the Forward Slash (/).
					    # There is also a 65th character known as a pad, which is the Equal sign (=). This character is used when the last
					    # segment of binary data doesn't contain a full 6 bits
					    if [[ ${report_compress_cmd} == *"/zip"*  ]]; then
					        #zip_cmd=${report_compress_cmd} -9 ${htm_with_params_in_name}.zip ${htm_with_params_in_name}
					        zip2b64_txt=${htm_with_params_in_name}.zip.b64.txt
					        zip_cmd="${report_compress_cmd} -9 --junk-paths - ${htm_with_params_in_name} | base64 > $zip2b64_txt"
					    elif [[ ${report_compress_cmd} == *"/7za"*  ]]; then
					        zip2b64_txt=${htm_with_params_in_name}.7z.b64.txt
					        zip_cmd="${report_compress_cmd} u dummy -tgzip -mx9 -mfb273 -so ${htm_with_params_in_name} | base64 > ${htm_with_params_in_name}.7z.b64.txt"
					        #zip_cmd="${report_compress_cmd} u $tmpauxtmp -mx9 -mfb273 ${htm_with_params_in_name}; cat $tmpauxtmp | base64 > $zip2b64_txt ; rm -f $tmpauxtmp"
					    elif [[ ${report_compress_cmd} == *"/zstd"*  ]]; then
					        zip2b64_txt=${htm_with_params_in_name}.zst.b64.txt
					        zip_cmd="${report_compress_cmd} --stdout -19 ${htm_with_params_in_name} | base64 > $zip2b64_txt"
					    else
					        sho "Unsupported command for compress HTML results: {report_compress_cmd}" $plog
					    fi
					fi
					
					if [[ ${zip_cmd} == *"UNSUPPORTED"*  ]]; then
					    sho "HTML report is saved without compression" $plog
					    while read line; do
					        echo "insert into results_reports(run_id, txt) values(${v_run_id}, q'{${line} }');">>$psql
					    done < <( cat $htm_with_params_in_name )
					else
					    sho "HTML report is compressed and converted to base64 format before saving. Command:" $plog
					    sho "$zip_cmd" $plog
					    eval "$zip_cmd" 1>$tmpsidlog 2>$tmpsiderr
					    retcode=$?
					    cat $tmpsidlog >>$plog
					    cat $tmpsiderr >>$plog
					    if [[ $retcode -ne 0 ]]; then
					        catch_err $? $plog $tmpsiderr "Compression FAILED. Check log in $plog"
					    fi
					    while read line; do
					        echo "insert into results_reports(run_id, zip2b64) values(${v_run_id}, q'{${line}}');">>$psql
					    done < <( cat $zip2b64_txt )
					    echo "update results_overall o set o.report_compress_cmd='$report_compress_cmd' where o.run_id=${v_run_id};" >>$psql
					    rm -f $zip2b64_txt
					fi
					echo "commit;">>$psql

					run_cmd="$isql_name $host/$port:$results_fdb -i $psql -q -nod $dbauth -ch utf8"
					sho "Saving HTML report in $results_fdb, run_id=${v_run_id}. Command:" $plog
					sho "$run_cmd" $plog
					eval "$run_cmd" 1>$tmpsidlog 2>$tmpsiderr
					catch_err $? $plog $tmpsiderr "Check occurences of alternate quoting: q'{ ... }' withing strings in HTML"
					rm -f  $psql
				else
					sho "Can not save HTML report in $results_fdb: variable 'v_run_id' remains undefined." $plog
				fi # -n "$v_run_id" 
			fi

			# do not use '-se' here! Can fail for unknown reason!
			run_cmd="$fbc/gbak -b -user ${usr} -pas ${pwd} $results_fdb $results_fbk"
			sho "Make backup of new results, command:" $plog
			sho "$run_cmd" $plog
			eval "$run_cmd" 1>$tmpsidlog 2>$tmpsiderr
			catch_err $? $plog $tmpsiderr "Check whether database $results_fbk exists."
			rm -f $tmpsidlog $results_fdb

        fi

        rm -f $tmpauxlog
	rm -f $tmpdir/1stoptest.tmp.sh
	break

  fi
  # end of: $cancel_test= 1

  sho "SID=$sid. Finished packet $packet" $sts

  packet=$((packet+1))
done

rm -f  $tmpcharts

if [[ "$remove_isql_logs" == "never" ]]; then
    sho "SID=$sid. Bye-bye from $shname" $sts
else
    echo $(date +'%d.%m.%y %H:%M:%S') SID=$sid. Bye-bye from $shname
    rm -f $log $err $sts $sid_starter_sql
fi

if [ $sid -eq 1 ]; then
    if [ -s $plog ]; then
        sho "SID=$sid. Final point of $shname. Bye-bye." $plog
	cat <<- EOF

		$(date +'%d.%m.%y %H:%M:%S'). SID=1. Final report see in: 
		##############################################
		$plog
		##############################################

	EOF
	sleep 1
	if [[ -f "$plog" ]]; then
	    touch $plog
	fi
    else
	cat <<- EOF

		$(date +'%d.%m.%y %H:%M:%S'). SID=1. Could not find final report: no file with name 'plog'=$plog

	EOF
    fi
fi
exit
