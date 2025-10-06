import os
import sys
import inspect
import socket
import subprocess
import tempfile
import operator
import platform
import codecs
from collections import defaultdict
import difflib
import html
import locale
import base64
# yum -y install python-pip
# pip install --upgrade pip
# pip install fdb

# This package allows to obtain .fbt into dict, see ast.literal_eval() call:
import ast

from shutil import copyfile
import datetime
import time
#import fdb
import firebird.driver
from firebird.driver import *
from urllib.parse import quote
from pathlib import Path

whoami=os.path.realpath(__file__)

#-----------------------
class Logger(object):
    def __init__(self, log_file, wr_mode ):
        self.stdout = sys.stdout
        self.terminal = sys.stdout
        self.log = open( log_file, wr_mode )
    def __del__(self):
        sys.stdout = self.stdout
        self.log.close()

    def write(self, message):
        self.terminal.write( message )
        self.log.write(message)
    def flush(self):
        self.terminal.flush()
        self.log.flush()

#-----------------------

def showtime():
     global datetime
     return ''.join( (datetime.datetime.now().strftime("%y%m%d_%H%M%S"),'.') )

#-----------------------

def generate_html_head( css_page ):
    html_head = \
'''<html>
<head>
    <meta http-equiv="content-type" content="text/html; charset=utf-8" />
    <meta http-equiv="cache-control" content="no-cache">
    <meta http-equiv="pragma" content="no-cache">
    <link rel="stylesheet" type="text/css" href="%(css_page)s">
    <!--
         https://stackoverflow.com/questions/22607150/getting-the-url-parameters-inside-the-html-page
         https://stackoverflow.com/questions/12042592/decoding-url-parameters-with-javascript
    -->

    <script>
        // Parsing URL of this document and extract from there value for 'page_title' key.
        urlp = [];
        // console.log( location.toString() );
        s = location.toString().split('?');
        if (s.length >= 2) {
            s = s[1].split('&');
            for( i=0; i<s.length; i++ ) {
                u = s[i].split('=');
                urlp[ u[0] ] = u[1];
                // console.log( 'urlp[ u[0] ]=' + urlp[ u[0] ] + ': '  + u[1] );
            }
            top.document.title = decodeURIComponent( (urlp['page_title']+'').replace(/\\+/g, '%%20') );
        }
    </script>

    <!--
        all web pages with Google Charts should include the following lines in the <head> of the web page:
        https://developers.google.com/chart/interactive/docs/basic_load_libs
        :::: ACHTUNG ::::
        do NOT put these lines into each chart js-block, otherwise runtime exception occurs:
        "too much recursion" (Firefox) or "Maximum call stack size exceeds" (Chrome)
        See: https://groups.google.com/forum/#!topic/Google-Visualization-Api/iigCT7a-MFk
        Post by Luis Rito:
        "I just had to put google.charts.load(...) on the head of the WEB PAGE instead of putting on every .js file"
    -->
    <script type="text/javascript" src="https://www.gstatic.com/charts/loader.js"></script>
    <script type="text/javascript">
        google.charts.load('current', {'packages':['corechart']});
    </script>


</head>
''' % locals()
    return html_head

#--------------------------

def extract_detailed_report( con, rec, fb_prefix, html_path ):
    # fb_prefix = 'fb3x_', 'fb4x_', 'fb5x_'

    run_id = str(rec[ fb_prefix+'run_id'])
    build_no = rec[ fb_prefix+'vers'].split('.')[-1]
    decode_from_b64 = False

    if not rec[ fb_prefix + 'compress_cmd']:
        # This text was converted to base-64 format WITHOUT compression
        # (e.g. on POSIX when test config parameter 'report_compressor' is commented out)
        # Now we have to decode it to be readable view and store directly to .html
        detl_ext = '.html'
        decode_from_b64 = True
    else:

        #print("rec[ fb_prefix+'compress_cmd' ]=",rec[ fb_prefix+'compress_cmd' ])

        if '/' in rec[ fb_prefix+'compress_cmd' ]:
            # Test ran on Linux, report was compressed by one of folowing:
            # /usr/bin/gzip ;  /usr/bin/7za ; /usr/bin/zstd ; /usr/bin/zip
            compress_base = rec[ fb_prefix+'compress_cmd'].split('/')[-1].lower()
        else:
            # Test ran on Windows, report was compressed by one of folowing:
            # c:\...\7z.exe ; c:\...\zstd.exe ; cscript <vbs_for_ZIP>
            compress_base = os.path.splitext(rec[ fb_prefix+'compress_cmd'].split('\\')[-1])[0].lower()

        if compress_base in ('7z', '7za', 'gzip'):
            # NB: 'gzip' not present as standalone utility for Windows.
            # 7-Zip can extract from compressed file created by gzip even if extenstion
            # of such (compressed) file was changed to .7z
            # (warning will be issued in this case but extraction will be completed OK).
            detl_ext = '.7z'
        elif compress_base in ('zstd', 'zst'):
            # !!NB!! compressor 'zstd' expected extension of file '.zst', NOT '.zstd' !
            detl_ext = '.zst'
        else:
            detl_ext = '.zip'

        # NB do not change extension '.b64'! main batch scenario (oltp_overall_report.sh/.bat) will search
        # for all files that have this extension and run decoding of them to readable text!
        detl_ext += '.b64'

        print('run_id=',run_id,', build_no=',build_no,'; compress_cmd=',rec[ fb_prefix+'compress_cmd' ],'; compress_base=',compress_base,'; detl_ext=',detl_ext)

  
    # Extract report for this OLTP-EMUL run and store in html_path
    ################

    detl_rows = []
    with con.cursor() as c_report:
        c_report.execute( 'select txt, zip2b64 from sp_show_report_data( ?, ?)', (build_no, run_id, ) )
        # curr func: extract_detailed_report
        # FDB driver .fetchallmap(): returns a list of mappings of field name to field value, rather than a list of tuples.
        # firebird-driver .to_dict(): Returns row tuple as dictionary with field names as keys.
        for r in c_report:
            detl_rows.append(c_report.to_dict(r))

    #print('chk detl_rows{}:')
    #for k,v in detl_rows.items():
    #    print(k,':::',v)
    #print('$$$$$$$$$$$$$$$$$$$$$$$$')
    print(f'{len(detl_rows)=}')

    html_file = None
    if detl_rows:
        file_pref = 'oltp-report_build_' +build_no + '_run_' + run_id
        detl_file = os.path.join(html_path, file_pref + detl_ext )
        html_file = os.path.join(html_path, file_pref + '.html')

        if decode_from_b64: # not rec[ fb_prefix+'compress_cmd']:
            # field fbNN_compress_cmd is NULL --> we have to decode text in base-64 format
            # that was previously encoded in 'oltp_isql_run_worker' batch scenario for POSIX:
            # while read line; do
            #     echo "insert into results_reports(run_id, txt) values(${v_run_id}, '${line}');">>$psql
            # done < <( cat $htm_with_params_in_name | base64 )
            # ::: NB::: On Windows this can not occur because any text is compressed even when parameter
            # 'compress_cmd' is commented out: batch oltp_isql_run_worker.bat creates temporary .vbs script
            # and uses built-in ability to compress text/html to .zip format.

            # Do this from 'txt' field directly to .html-file:
            print(f'field fbNN_compress_cmd is NULL, output from TXT to {detl_file=}')
            with codecs.open( detl_file, 'w', encoding='utf-8') as f:
                for t in [ t for t in detl_rows if t['TXT'] ]:
                    f.write( base64.b64decode( t['TXT'] ).decode("utf-8") )
        else:
            # field fbNN_compress_cmd is NOT null --> output base64 data from 'zip2b64' field.
            # Decoding it to binary (.zip/.7z/.zst) and decompressing to html will be done 
            # by batch scenario AFTER this .py script completed.
            # ::: NB :::
            #####################################################################################
            # detl_file must have extension = '.b64' because batch scenario after this .py script
            # (oltp_overall_report.bat / oltp_overall_report.sh ) will search all files with this mask
            # for decoding them to apropriate target:
            # Windows: for /f %%a in ('dir /b !DETAILS_DIR!\*.b64') do ...
            # POSIX:   b64list=$DETAILS_DIR/*.b64 ; for b in $b64list do ...
            #####################################################################################
            print(f'field fbNN_compress_cmd is NOT null, output from ZIP2B64 to {detl_file=}')
            with codecs.open( detl_file, 'w') as f:
                for t in [t for t in detl_rows if  t['ZIP2B64'] ]:
                    f.write( t['ZIP2B64'] + '\n' )

            #print('created file ', f.name)

    # We return name of HTML file in order to have link to open it
    # when click on some cell with performance value in the table:
    return html_file

# end of extract_detailed_report

#--------------------------

# 19.12.2020
def extract_stack_traces( con, rec, fb_prefix, html_path ):
    # fb_prefix = 'fb3x_', 'fb4x_', 'fb5x_'

    run_id = str(rec[ fb_prefix+'run_id'])
    build_no = rec[ fb_prefix+'vers'].split('.')[-1]

    if not rec[ fb_prefix + 'compress_cmd']:
        # NB: stack trace text was preliminary converted to base64 format.
        # we have decode it (here), output file will be readable
        detl_ext = '.b64'
    else:
        # stack trace was preliminary compressed and cthen converted to base64 format.
        #print("rec[ fb_prefix+'compress_cmd' ]=",rec[ fb_prefix+'compress_cmd' ])

        if '/' in rec[ fb_prefix+'compress_cmd' ]:
            # /usr/bin/zip ; /usr/bin/7za ; /usr/bin/zst
            compress_base = rec[ fb_prefix+'compress_cmd' ].split('/')[-1].lower()
        else:
            # c:\...\7z.exe ; c:\...\zstd.exe etc
            compress_base = os.path.splitext(rec[ fb_prefix+'compress_cmd' ].split('\\')[-1])[0].lower()
        
        #print('compress_base=',compress_base)

        if compress_base in ('7z', '7za'):
            detl_ext = '.7z'
        elif compress_base in( 'zstd', 'zst'):
            detl_ext = '.zst'
        else:
            detl_ext = '.zip'

        # NB do not change extension '.b64'! main batch scenario (oltp_overall_report.sh.sh/.bat) will search
        # for all files that have this extension and run decoding of them to readable text!
        detl_ext += '.b64'
  
    # Extract 'heading info' about all crashes occured durint this OLTP-EMUL run
    ########################
    crashes_list = []
    with con.cursor() as c_crash_list:
        c_crash_list_sql='''
            select id,dumpname,dumpsize,dumptime,crashed_binary,stack_trace_validation_result,stack_trace_size
            from all_fb_crash_list
            where fb_build_no = ? and run_id = ?
        '''
        c_crash_list.execute( c_crash_list_sql, (build_no, run_id,) )

        # curr func: extract_stack_traces
        # FDB driver .fetchallmap(): returns a list of mappings of field name to field value, rather than a list of tuples.
        # firebird-driver .to_dict(): Returns row tuple as dictionary with field names as keys.
        for r in c_crash_list:
            crashes_list.append(c_crash_list.to_dict(r))
    
    # Output arg: list of .b64 files, for each record of all_fb_crash_list
    htm_crashes_info_list = []
    b64_stack_traces_list = []
    
    for crash_rec in crashes_list:
        file_pref = '_'.join( ('oltp-crash-build',build_no, 'run', run_id, 'id', str(crash_rec['ID']) ) )
        dumpname=crash_rec['DUMPNAME']
        dumpsize=crash_rec['DUMPSIZE']
        dumptime=crash_rec['DUMPTIME']
        crashed_binary=crash_rec['crashed_binary'.upper()]
        stack_trace_validation_result=crash_rec['stack_trace_validation_result'.upper()]
        stack_trace_size=crash_rec['stack_trace_size'.upper()]

        # oltp-crash-build_33400_run_3052_id_3329.20201219_094111.649.html
        html_file = os.path.join(html_path, file_pref + '.' + dumptime.strftime("%Y%m%d_%H%M%S.%f")[:19] + '.html')
        # oltp-crash-build_33400_run_3052_id_3329.20201219_094111.649.zip.b64
        detl_file = os.path.join(html_path, file_pref + '.' + dumptime.strftime("%Y%m%d_%H%M%S.%f")[:19] + detl_ext )

        htm_crashes_info_list.append( html_file )
        b64_stack_traces_list.append( detl_file )

        with codecs.open( html_file, 'w', encoding='utf-8') as f_heading_info:
        
            html_text='''\
                <html>
                <head>
                <meta http-equiv="content-type" content="text/html; charset=utf-8" />
                <meta http-equiv="cache-control" content="no-cache">
                <meta http-equiv="pragma" content="no-cache">
                </head>
                <body>
                Dump file:
                <li>Name: %(dumpname)s</li>
                <li>Size: %(dumpsize)s</li>
                <li>Time: %(dumptime)s</li>
                Crashed binary: %(crashed_binary)s
                Stack trace:
                <li>Validation result: %(stack_trace_validation_result)s</li>
                <li>Size: %(stack_trace_size)s</li>
                <p>
                <!-- </body> -->
                <!-- </html> -->
            ''' % locals()
            f_heading_info.write(
                #base64.b64encode( bytes(htm2b64, 'utf-8') )
                html_text
                #os.linesep.join( html_text.split() )
            )


        # Obtain stack trace data: it is in base64 format and represent compressed text (.7z/.zst/.zip)
        # This data are store in the file with extension '.b64':
        crashes_data = []
        with con.cursor() as c_crash_data, \
             codecs.open( detl_file, 'w') as f_stack_trace:

            c_crash_data_sql='select txt2b64, zip2b64 from all_fb_crash_data where fb_build_no = ? and run_id = ?'
            c_crash_data.execute( c_crash_data_sql, (build_no, run_id,) )
            # curr func: extract_stack_traces
            # FDB driver .fetchallmap(): returns a list of mappings of field name to field value, rather than a list of tuples.
            # firebird-driver .to_dict(): Returns row tuple as dictionary with field names as keys.
            for r in c_crash_data:
                crashes_data.append(c_crash_data.to_dict(r))

        for stack_trace_rec in crashes_data:
            if not rec[ fb_prefix+'compress_cmd' ]:
                f_stack_trace.write( stack_trace_rec['TXT2B64']+'\n' )
            else:
                f_stack_trace.write( stack_trace_rec['ZIP2B64']+'\n' )
    
    # Return LIST of .html files which will be later completer with stack trace data.
    # A new file is created or each FB crash.
    #return (htm_crashes_info_list, b64_stack_traces_list)
    return htm_crashes_info_list
# end of extract_stack_traces

#------------------------------------

def write_chart_script_beg( main_html_file, attrib_map ):

    divName = attrib_map['divName'] # mandatory: perf_memo_used_all_div etc
    drawFunc = attrib_map['drawFunc'] # mandatory: 'draw_memo_used_all' etc
    divWidth = attrib_map.get('divWidth', DEFAULT_CHART_DIV_WIDTH) # optional: width of chart
    divHeight = attrib_map.get( 'divHeight', DEFAULT_CHART_DIV_HEIGHT) # optional: height of chart
    chart_script_beg=\
    '''
<div id="%(divName)s" style="width: %(divWidth)spx; height: %(divHeight)spx;"></div>
<script type="text/javascript">
    // see settings here: https://developers.google.com/chart/interactive/docs/
    google.charts.setOnLoadCallback( %(drawFunc)s );
    function %(drawFunc)s() {
        var data = google.visualization.arrayToDataTable([
    ''' % locals()

    main_html_file.write( '\n'.join([x.rstrip() for x in chart_script_beg.splitlines()]) )

# end of write_chart_script_beg

#-------------------------------------
def write_chart_data( main_html_file, chart_data, points_limit, brand_mnemona, checked_major_vers_lst, this_chart_fields_lst, values_fmt, values_descr ):
    # checked_major_vers_lst = '6x,5x,4x'
    # this_chart_fields_lst:
    #     ['fb6x_perf_score', 'fb5x_perf_score', 'fb4x_perf_score']
    i=0
    # values_descr = 'peak memory used by statements';
    print(f'{checked_major_vers_lst=}')
    print(f'{this_chart_fields_lst=}')
    for r in chart_data:
        if i==0:
            col_hints = [ "''" ] # no title in the chart for 'run_date' column
            print(f'{checked_major_vers_lst=}')
            for major_vers_suffix in [x for x in checked_major_vers_lst.split(',') if x]: # ['6x','5x','4x'] etc
                # NOTE: if all values for some column are nulls then we have to specify its type in form
                # {label: '....', type: 'number'} -- otherwise google charts raise
                # "All series on a given axis must be of the same data"
                # Possible solution for this:
                # https://stackoverflow.com/questions/13216377/google-chart-api-error-all-series-on-a-given-axis-must-be-of-the-same-data-type
                # {label: 'FB-5x peak memory used for DB level', type: 'number'}
                col_hints.append(f"{{label: '{brand_mnemona.upper()}-{major_vers_suffix} {values_descr}', type: 'number'}}") # we have to specify '{' and '}' twise if use f-notation!

            main_html_file.write( " "*12 + '[' + ','.join(col_hints) + ', ]\n' )

        col_vals = []
        for fld_i in this_chart_fields_lst:
            if r[fld_i]:
                col_vals.append( values_fmt.format( r[fld_i] ) )
            else:
                col_vals.append( 'null' )

        main_html_file.write( " "*12 + ",[ '" +  r['run_date'].strftime("%d.%m.%y") + "', " + ','.join(col_vals) + "]\n" )
        print('col_vals=',col_vals)

        #fb3x_field_value, fb4x_field_value, fb5x_field_value = 'null', 'null', 'null'
        #if r[fb3x_field_name]:
        #    fb3x_field_value = values_fmt.format( r[fb3x_field_name] )
        #if r[fb4x_field_name]:
        #    fb4x_field_value = values_fmt.format( r[fb4x_field_name] )
        #if r[fb5x_field_name]:
        #    fb5x_field_value = values_fmt.format( r[fb5x_field_name] )

        #main_html_file.write( "\n" + " "*12 + ",[ '" +  r['run_date'].strftime("%d.%m.%y") + "', " + fb3x_field_value + "," + fb4x_field_value + "," + fb5x_field_value + "]" )
        #print( " "*12 + ",[ '" +  r['run_date'].strftime("%d.%m.%y") + "', " + fb3x_field_value + "," + fb4x_field_value + "," + fb5x_field_value + "]" )
        i += 1
        if ( i>= points_limit):
            break
# end of write_chart_data

#------------------------------------
def write_chart_script_end( main_html_file, attrib_map ):

    chartType = attrib_map['chartType'] # mandatory
    colorList = attrib_map['colors'] # mandatory
    divname = attrib_map['divName'] # mandatory

    curveType = attrib_map.get('curveType') # optional
    fractionDigits = attrib_map.get('fractionDigits', 2)

    GROUPING_DIGITS_CHAR = ' '

    # 05.10.2020
    chartAreaLeft = attrib_map.get( 'chartAreaLeft', DEFAULT_CHART_AREA_LEFT) # optional: value for 'chartArea{ left:NNN, ...}'; value must NOT be less than 100!
    chartAreaTop= attrib_map.get('chartAreaTop', DEFAULT_CHART_AREA_TOP) # optional:  value for 'chartArea{ ..., top:NNN}'; value must NOT be less than 20!

    chartAttr = "var chart = new google.visualization.%(chartType)s( document.getElementById('%(divname)s') );" % locals()
    colorAttr = "colors: " + str(colorList).strip('()') + ","
    curveAttr = "curveType: '%(curveType)s'," % locals() if curveType else ''

    #fmt_command = "fmt = new google.visualization.NumberFormat({  pattern:'0' });"
    # https://developers.google.com/chart/interactive/docs/reference?hl=en#numberformatter
    fmt_command = "fmt = new google.visualization.NumberFormat( {fractionDigits: %d, groupingSymbol: '%s'} );\n" % (fractionDigits, GROUPING_DIGITS_CHAR)

    # https://developers.google.com/chart/interactive/docs/reference?hl=en#formatters
    # Formatters only affect one column at a time; to reformat multiple columns, apply a formatter to each column that you want to change.
    # NOTE: we assume that data with memory consumption occupies columns 1,2 and 3 (for FB 3.x, 4.x and 5.x):
    fmt_command += '\n'.join ( [ ' '*8 + f'fmt.format(data, {i+1});' for i,x in enumerate(colorList) ] )
    
    #print(attrib_map)
    #print('colorList=',colorList)
    #print('fmt_command=',fmt_command)
    #print('HHHHHHHHHHHHHH')

    # Result:
    #    fmt.format(data, 1);
    #    fmt.format(data, 2);
    #    fmt.format(data, 3);
                                
    # 19.08.2020: added 'chartArea:{left:N, top:M}'in order to adjust chart to the left margin of page.
    # NB do not set 'left' in chartArea less than 100 otherwise number on vertical axis will be hidden.
    chart_script_end=\
    '''        ]);
        %(fmt_command)s
        var options = {
                    title: '',
                    pointSize: 3,
                    legend:{ position:'top', maxLines: 3 },
                    chartArea:{left:%(chartAreaLeft)s, top:%(chartAreaTop)s},
                    %(colorAttr)s
                    %(curveAttr)s

                    hAxis: {
                         title: '',
                         format: '0',
                         slantedText: true,
                         textStyle: {
                           color: 'DarkBlue',
                           bold: false,
                           italic: false,
                           fontSize: 10
                         },
                    },
                    vAxis: {
                         title: '',
                         minValue: 0,
                         textStyle: {
                           color: 'DarkBlue',
                           bold: false,
                           italic: false,
                           fontSize: 10
                         }
                    }
        }

        %(chartAttr)s;
        chart.draw(data, options);
    }
</script>
    ''' % locals()

    main_html_file.write( chart_script_end )

# end of write_chart_script_end

###############################
###   m a i n    p a r t    ###
###############################

this_base_name = os.path.splitext( os.path.realpath(sys.argv[0]) )[0]

# Log for duplicating STDOUT messages:
os.environ["PYTHONUNBUFFERED"] = "1"
LOG4DUP_STDOUT = os.environ.get('PYTHON_CALLER_JOBLOG')
LOG4DUP_WRMODE = 'a'
if not LOG4DUP_STDOUT:
    LOG4DUP_STDOUT = ''.join(  (  this_base_name, '.tmp', '.log' ) )
    LOG4DUP_WRMODE = 'w'

init_stdout = sys.stdout
sys.stdout = Logger( LOG4DUP_STDOUT, LOG4DUP_WRMODE )

print(showtime(), 'Intro '+ whoami + '. Python version: ' + platform.python_version() )

FB_CLNT=os.environ.get( 'FB_CLNT', os.path.join( os.environ['HEAD_FBC'], 'fbclient.dll' ) )
DB_NAME=os.environ['DB_OVERALL_FILE']
DB_USER=os.environ['DBA_USER']
DB_PSWD=os.environ['DBA_PSWD']

TMPPATH=os.environ['LOGDIR']

# "c:\temp\...\details" - place for storing run reports
DETLPATH=os.environ['DETAILS_DIR']

# "details" - name for reltive paths:
DETLPREF=DETLPATH.split(os.sep)[-1]

FB_HOME=os.path.dirname(os.path.abspath(FB_CLNT))
MAJOR_VERSIONS_LST=os.environ['MAJOR_VERSIONS_LST'] # 6x,5x,4x

MAX_ROWS_IN_REPORT=int(os.environ['MAX_ROWS_IN_REPORT'])
MAX_POINTS_IN_CHART=int(os.environ['MAX_POINTS_IN_CHART'])

# Default values for width and height of areas for charts drawing.
# Used for assigning to divWidth and divHeight in write_chart_script_beg()
DEFAULT_CHART_DIV_WIDTH=int(os.environ['DEFAULT_CHART_DIV_WIDTH'])
DEFAULT_CHART_DIV_HEIGHT=int(os.environ['DEFAULT_CHART_DIV_HEIGHT'])

DEFAULT_CHART_AREA_LEFT=int(os.environ['DEFAULT_CHART_AREA_LEFT'])
DEFAULT_CHART_AREA_TOP=int(os.environ['DEFAULT_CHART_AREA_TOP'])

CHART_COLORS_PERF_SCORE=os.environ['CHART_COLORS_PERF_SCORE']
CHART_COLORS_MEMO_ALL=os.environ['CHART_COLORS_MEMO_ALL']
CHART_COLORS_MEMO_ATT=os.environ['CHART_COLORS_MEMO_ATT']
CHART_COLORS_MEMO_TRN=os.environ['CHART_COLORS_MEMO_TRN']
CHART_COLORS_MEMO_STM=os.environ['CHART_COLORS_MEMO_STM']

MAIN_RPT_FILE=os.environ['MAIN_RPT_FILE']

BRAND_MNEMONA=os.environ['BRAND_MNEMONA'] # 'fb' or 'hq'

#######################################

driver_config.fb_client_library.value = FB_CLNT
srv_config = driver_config.register_server(name = 'qa_overall_report_srv', config = '')
db_cfg_object = driver_config.register_database(name = 'qa_overall_report_db')
db_cfg_object.server.value = srv_config.name
db_cfg_object.database.value = DB_NAME
db_cfg_object.no_linger.value=True
db_cfg_object.forced_writes.value = False
# db_cfg_object.protocol.value = NetProtocol.XNET if os.name =='nt' else NetProtocol.INET
db_cfg_object.protocol.value = NetProtocol.INET
db_cfg_object.charset.value = 'utf8'
db_cfg_object.user.value = DB_USER
db_cfg_object.password.value = DB_PSWD

with connect( db_cfg_object.name, user = db_cfg_object.user.value, password = db_cfg_object.password.value, charset = db_cfg_object.charset.value, no_gc=1, no_db_triggers=1) as con, \
     codecs.open( os.path.join(TMPPATH, MAIN_RPT_FILE), 'w', encoding='utf-8') as main_html_file:
    print('Established connection to',con.info.firebird_version)
    main_html_file = codecs.open( os.path.join(TMPPATH, MAIN_RPT_FILE), 'w', encoding='utf-8')

    main_css_file = os.path.join(TMPPATH, os.path.splitext(MAIN_RPT_FILE)[0]+'.css' )

    copyfile( this_base_name+'.css', main_css_file)

    # Output HEAD section:
    ######################
    main_html_file.write( generate_html_head( os.path.split(main_css_file)[1] ) )
    main_html_file.write('<body>')

    href_lst=\
    '''
    <ol>
        <li><a href=#perf_score_chart>Performance score, chart</a></li>
        <li><a href="#memo_used_all_chart">Memory usage for DB level, chart</a></li>
        <li><a href="#memo_used_att_chart">Memory usage for attachments, chart</a></li>
        <li><a href="#memo_used_trn_chart">Memory usage for transactions, chart</a></li>
        <li><a href="#memo_used_stm_chart">Memory usage for statements, chart</a></li>
        <li><a href="#overall_results_table">All results, table</a></li>
    </ol>
    '''
    main_html_file.write(href_lst)

    print('html report see in: ',os.path.join(TMPPATH, MAIN_RPT_FILE))
    fb_vers_cols = []
    fb_perf_cols = []
    fb_mem_all_suff = []
    fb_mem_all_cols = []

    fb_mem_att_suff = []
    fb_mem_att_cols = []

    fb_mem_trn_suff = []
    fb_mem_trn_cols = []

    fb_mem_stm_suff = []
    fb_mem_stm_cols = []

    fb_outcome_suff = []
    fb_outcome_cols = []

    fb_run_hhmm_suff = []
    fb_run_hhmm_cols = []

    fb_run_id_cols = []
    fb_compress_cols = []

    for v in [x for x in MAJOR_VERSIONS_LST.split(',') if x]:
        fb_vers_cols.append( f'"fb{v}_vers"' )
        fb_perf_cols.append( f'"fb{v}_perf_score"' )

        fb_mem_all_suff.append(f'"fb{v} mem, ALL"')
        fb_mem_all_cols.append( f'cast("fb{v}_used_all" / (1024.00*1024) as numeric(12,2)) as {fb_mem_all_suff[-1]}' )

        fb_mem_att_suff.append(f'"fb{v} mem, att"')
        fb_mem_att_cols.append( f'cast("fb{v}_used_by_att" / (1024.00*1024) as numeric(12,2)) as {fb_mem_att_suff[-1]}' )

        fb_mem_trn_suff.append(f'"fb{v} mem, trn"')
        fb_mem_trn_cols.append( f'cast("fb{v}_used_by_trn" / (1024.00*1024) as numeric(12,2)) as {fb_mem_trn_suff[-1]}' )

        fb_mem_stm_suff.append(f'"fb{v} mem, stm"')
        fb_mem_stm_cols.append( f'cast("fb{v}_used_by_stm" / (1024.00*1024) as numeric(12,2)) as {fb_mem_stm_suff[-1]}' )

        fb_outcome_suff.append(f'"fb{v} result"')
        fb_outcome_cols.append( f'"fb{v}_outcome" as {fb_outcome_suff[-1]}')

        fb_run_hhmm_suff.append(f'"fb{v}_run_hhmm"')
        fb_run_hhmm_cols.append( f'"fb{v}_run_hhmm" as {fb_run_hhmm_suff[-1]}')

        fb_run_id_cols.append( f'"fb{v}_run_id"' )
        fb_compress_cols.append( f'"fb{v}_compress_cmd"' )

    stm = f'''
        select
            "run_date"
            ,"run_seqn"
            ,{'\n,'.join(fb_vers_cols)}
            ,{'\n,'.join(fb_perf_cols)}
            ,{'\n,'.join(fb_mem_all_cols)}
            ,{'\n,'.join(fb_mem_att_cols)}
            ,{'\n,'.join(fb_mem_trn_cols)}
            ,{'\n,'.join(fb_mem_stm_cols)}
            ,{'\n,'.join(fb_outcome_cols)}
            ,{'\n,'.join(fb_run_hhmm_cols)}
            ,{'\n,'.join(fb_run_id_cols)}
            ,{'\n,'.join(fb_compress_cols)}
        from sp_show_results( {MAX_POINTS_IN_CHART} ) -- returns data in order: run_date desc, run_seqn asc
    '''
    print('stm=',stm)

    #if MAX_ROWS_IN_REPORT > 0:
    #    stm += ' rows ' + str( MAX_ROWS_IN_REPORT )

    perf_score_hint='number of successfully completed business actions per minute, average for test_time interval'
    memo_used_hint='maximal value of mon$memory_usage.mon$memory_used during test_time interval'

    col_hints={
            "run_date" : "date of test run"
            ,"run_seqn" : "sequential number of this launch within date"
    }
    for v in [x for x in MAJOR_VERSIONS_LST.split(',') if x]:
        # Define tooltips for table columns:
        # <th title="HQ-5x, number of successfully completed business actions... ">fb5x perf score</th>
        # <th title="HQ-5x, maximal value of mon$memory_usage.mon$memory_used ... ">fb5x mem, ALL</th>
        col_hints[ f'fb{v}_vers' ] = f'{BRAND_MNEMONA.upper()}-{v} snapshot version'
        col_hints[ f'fb{v}_perf_score' ] = f'{BRAND_MNEMONA.upper()}-{v}, {perf_score_hint}'
        col_hints[ f'fb{v} mem, ALL' ] = f'{BRAND_MNEMONA.upper()}-{v}, {memo_used_hint}, for DATABASE level'
        col_hints[ f'fb{v} mem, att' ] = f'{BRAND_MNEMONA.upper()}-{v}, {memo_used_hint}, for ATTACHMENTS level'
        col_hints[ f'fb{v} mem, trn' ] = f'{BRAND_MNEMONA.upper()}-{v}, {memo_used_hint}, for TRANSACTIONS level'
        col_hints[ f'fb{v} mem, stm' ] = f'{BRAND_MNEMONA.upper()}-{v}, {memo_used_hint}, for STATEMENTS level'
        col_hints[ f'fb{v} result' ] = f'{BRAND_MNEMONA.upper()}-{v}, test outcome'

    print('col_hints:')
    for k,v in col_hints.items():
        print(k,':::',v)

    data_in_descending_order = []
    with con.cursor() as cur:
        cur.execute(stm)
        #cur.execute('select distinct trim(t.rdb$field_name) fld_name, trim(t.rdb$type) rdb_type, trim(t.rdb$type_name) type_name from rdb$types t rows 10')

        col=cur.description
        fields = [c[0] for c in col]
        ftypes = [c[1] for c in col]

        #fields= ['run_date', 'fb3x_vers', 'fb4x_vers', 'fb3x_perf_score', 'fb4x_perf_score', 'fb3x_used_all', 'fb4x_used_all', 'fb3x_used_by_att', 'fb4x_used_by_att', 'fb3x_used_by_trn', 'fb4x_used_by_trn', 'fb3x_used_by_stm','fb4x_used_by_stm', 'fb3x_run_hhmm', 'fb4x_run_hhmm', 'fb3x_outcome', 'fb4x_outcome']
        #ftypes= [<type 'datetime.date'>, <type 'str'>, <type 'str'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'str'>, <type 'str'>, <type 'str'>, <type 'str'>]

        print(showtime(), 'Gather data from sp_show_results...' )

        #################################
        ###  f e t c h  a l l  m a p  ###
        #################################
        # MAIN CODE:
        # curr func: extract_detailed_report
        # FDB driver .fetchallmap(): returns a list of mappings of field name to field value, rather than a list of tuples.
        # firebird-driver .to_dict(): Returns row tuple as dictionary with field names as keys.
        for r in cur:
            data_in_descending_order.append(cur.to_dict(r))

    print(showtime(), 'Completed. Number of records: ' + str(len(data_in_descending_order)) )

    #for i,p in enumerate(data_in_descending_order):
    #    print('i=',i)
    #    for k,v in p.items():
    #        print(k,':::',v)
  
    # Change order of data: we have to show charts in CHRONOLOGICAL order:
    data_in_chronological_order = sorted(data_in_descending_order, key=lambda x: ( x['run_date'], -x['run_seqn'] ) )

    print('fields=',fields)
    print('ftypes=',ftypes)
    print('data_in_descending_order=',data_in_descending_order)
    for d in data_in_descending_order:
        print(d)

    #locale.setlocale(locale.LC_ALL, '')
    #locale._override_localeconv = {'mon_thousands_sep': ' '}

    print(showtime(), 'Starting create code for drawing charts. Limit of points: %d' % MAX_POINTS_IN_CHART )

    print(showtime(), 'Output CHART: performance score' )
    #####################################################

    main_html_file.write( '<h4> <a name="perf_score_chart">Performance score: number of successfully completed business actions per minute, in average</a> </h4>' )

    # Output head section for chart:
    # --------------------------------
    chart_script_beg = write_chart_script_beg(
        main_html_file,
        {
             'divName'  : 'perf_total_chart_div'
            ,'drawFunc' : 'perf_total_chart'
        }
    )

    #        ,'legends'  : "['', 'FB 3.x performance score', 'FB 4.x performance score']"

    # Output data for chart:
    # ----------------------
    #write_chart_data( main_html_file, data_in_chronological_order, MAX_POINTS_IN_CHART, 'fb3x_perf_score', 'fb4x_perf_score', 'fb5x_perf_score', "{:9g}", 'performance score' )
    write_chart_data( main_html_file, data_in_chronological_order, MAX_POINTS_IN_CHART, BRAND_MNEMONA, MAJOR_VERSIONS_LST, [x.replace('"','') for x in fb_perf_cols], "{:9g}", 'performance score' )
    # Output tail for chart script:
    # ------------------------------
    #print('MAJOR_VERSIONS_LST=',MAJOR_VERSIONS_LST)
    #print( [ x.strip() for x in CHART_COLORS_PERF_SCORE.split(',')[:len(MAJOR_VERSIONS_LST.split(','))] ] )

    chart_script_end = write_chart_script_end(
        main_html_file, 
        {
            'colors': [x.strip() for x in CHART_COLORS_PERF_SCORE.split(',')[:len(MAJOR_VERSIONS_LST.split(','))] ],
            'curveType': 'function',
            'chartType': 'LineChart',
            'divName' : 'perf_total_chart_div',
            'fractionDigits' : 0
        }
    )

    print(showtime(), 'Completed.' )
    ################################

    #+-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-+

    print(showtime(), 'Output CHART: peak memory used, for DB-level, Mb')
    ######################################################

    main_html_file.write( '<h4> <a name="memo_used_all_chart">Memory usage: peak values of mon$memory_used for DB level, Mb</a> </h4>' )

    # Output head section for chart:
    #--------------------------------
    chart_script_beg = write_chart_script_beg( 
        main_html_file,
        {
            'divName' : 'perf_memo_used_all_div',
            'drawFunc' : 'draw_memo_used_all'
        }
    )


    # Output data for chart:
    # ----------------------
    #write_chart_data( main_html_file, data_in_chronological_order, MAX_POINTS_IN_CHART, 'fb3x mem, ALL', 'fb4x mem, ALL', 'fb5x mem, ALL', "{:.2f}", 'peak memory used for DB level' )
    write_chart_data( main_html_file, data_in_chronological_order, MAX_POINTS_IN_CHART, BRAND_MNEMONA, MAJOR_VERSIONS_LST,  [x.replace('"','') for x in fb_mem_all_suff], "{:.2f}", 'peak memory used for DB level' )


    # Output tail for chart script:
    # ------------------------------
    chart_script_end = write_chart_script_end(
        main_html_file, 
        { 
            'colors': [x.strip() for x in CHART_COLORS_MEMO_ALL.split(',')[:len(MAJOR_VERSIONS_LST.split(','))] ],
            'curveType': 'function',
            'chartType': 'LineChart',
            'divName' : 'perf_memo_used_all_div',
            'fractionDigits' : 2
        }
    )

    print(showtime(), 'Completed.' )


    #+-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-+

    print(showtime(), 'Output CHART: peak memory used, ATTACHMENTS level, Mb')
    ##############################################################

    main_html_file.write( '<h4> <a name="memo_used_att_chart">Memory usage: peak values of mon$memory_used for attachments, Mb</a> </h4>' )

    # Output head section for chart:
    # --------------------------------
    chart_script_beg = write_chart_script_beg( 
        main_html_file,
        {
            'divName' : 'perf_memo_used_att_div',
            'drawFunc' : 'draw_memo_used_att'
        }
    )


    # Output data for chart:
    # ----------------------
    #write_chart_data( main_html_file, data_in_chronological_order, MAX_POINTS_IN_CHART, 'fb3x mem, att', 'fb4x mem, att', 'fb5x mem, att', "{:.2f}", 'peak memory used by attachments' )
    write_chart_data( main_html_file, data_in_chronological_order, MAX_POINTS_IN_CHART, BRAND_MNEMONA, MAJOR_VERSIONS_LST,  [x.replace('"','') for x in fb_mem_att_suff], "{:.2f}", 'peak memory used by attachments' )


    # Output tail for chart script:
    # ------------------------------
    chart_script_end = write_chart_script_end(
        main_html_file, 
        { 
            'colors': [x.strip() for x in CHART_COLORS_MEMO_ATT.split(',')[:len(MAJOR_VERSIONS_LST.split(','))] ],
            'curveType': 'function',
            'chartType': 'LineChart',
            'divName' : 'perf_memo_used_att_div',
    	    'fractionDigits' : 2
        }
    )

    print(showtime(), 'Completed.')

    #+-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-+

    print(showtime(), 'Output CHART: peak memory used, TRANSACTIONS level, Mb')
    ################################################################

    main_html_file.write( '<h4> <a name="memo_used_trn_chart">Memory usage: peak values of mon$memory_used for transactions, Mb</a> </h4>' )

    # Output head section for chart:
    # --------------------------------
    chart_script_beg = write_chart_script_beg( 
        main_html_file,
        {
            'divName' : 'perf_memo_used_trn_div',
            'drawFunc' : 'draw_memo_used_trn'
        }
    )


    # Output data for chart:
    # ----------------------
    #write_chart_data( main_html_file, data_in_chronological_order, MAX_POINTS_IN_CHART, 'fb3x mem, trn', 'fb4x mem, trn', 'fb5x mem, trn', "{:.2f}", 'peak memory used by transactions' )
    write_chart_data( main_html_file, data_in_chronological_order, MAX_POINTS_IN_CHART, BRAND_MNEMONA, MAJOR_VERSIONS_LST,  [x.replace('"','') for x in fb_mem_trn_suff], "{:.2f}", 'peak memory used by transactions' )


    # Output tail for chart script:
    # ------------------------------
    chart_script_end = write_chart_script_end(
        main_html_file, 
        { 
            'colors': [x.strip() for x in CHART_COLORS_MEMO_TRN.split(',')[:len(MAJOR_VERSIONS_LST.split(','))] ],
            # 'chartType': 'ScatterChart',
            'curveType': 'function',
            'chartType': 'LineChart',
            'divName' : 'perf_memo_used_trn_div',
            'fractionDigits' : 2
        }
    )

    print(showtime(), 'Completed.')

    #+-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-+

    print(showtime(), 'Output CHART: peak memory used, STATEMENTS level, Mb')
    ##############################################################

    main_html_file.write( '<h4> <a name="memo_used_stm_chart">Memory usage: peak values of mon$memory_used for statements, Mb</a> </h4>' )

    # Output head section for chart:
    # --------------------------------
    chart_script_beg = write_chart_script_beg(
        main_html_file, 
        {
            'divName' : 'perf_memo_used_stm_div',
            'drawFunc' : 'draw_memo_used_stm'
        }
    )


    # Output data for chart:
    # ----------------------
    #write_chart_data( main_html_file, data_in_chronological_order, MAX_POINTS_IN_CHART, 'fb3x mem, stm', 'fb4x mem, stm', 'fb5x mem, stm', "{:.2f}", 'peak memory used by statements' )
    write_chart_data( main_html_file, data_in_chronological_order, MAX_POINTS_IN_CHART, BRAND_MNEMONA, MAJOR_VERSIONS_LST,  [x.replace('"','') for x in fb_mem_stm_suff], "{:.2f}", 'peak memory used by statements' )

    # Output tail for chart script:
    # ------------------------------
    chart_script_end = write_chart_script_end(
        main_html_file, 
        { 
            'colors': [x.strip() for x in CHART_COLORS_MEMO_STM.split(',')[:len(MAJOR_VERSIONS_LST.split(','))] ],
            'curveType': 'function',
            'chartType': 'LineChart',
            'divName' : 'perf_memo_used_stm_div',
    	    'fractionDigits' : 2
        }
    )

    print(showtime(), 'Completed.')

    ###############
    # Output TABLE:
    ###############

    print(showtime(), 'Output TABLE with results.')
    ################################################

    main_html_file.write( '<h4><a name="overall_results_table">All results in one table. Unit of memory consumption: MB.</a></h4>' )
    main_html_file.write( '<p>Click on FB snapshot number to see detailed report for each run.<br></br>')
    main_html_file.write('\n<table class="t_table">')

    #######################
    # output column titles:
    #######################
    if os.environ['USE_PREDEFINED_TABLE_HDR']:
        # smth was for debug (maybe...); to be deleted later!
        with open(os.environ['USE_PREDEFINED_TABLE_HDR']) as f:
            results_table_header = f.read()
            results_table_header = results_table_header.format(**locals())
        main_html_file.write(results_table_header)

    else:

        for h in fields:
            v_tooltip = col_hints.get(h)

            if h.lower() == 'run_seqn' or h.lower().endswith('run_id') or h.lower().endswith('compress_cmd') or h.lower().endswith('run_hhmm'):
                # Do not show these columns.
                ### NOP ###
                continue

            #if h.lower().endswith('run_hhmm'):
            #    h = h.replace('run_hhmm', 'run hh:mm')

            # Output column title and its hint:
            if 'perf' in h or 'vers' in h or 'mem' in h:
                h = BRAND_MNEMONA.upper() + '-' + h[2:] # 'fb5x perf score' --> 'FB-5x perf score' or 'HQ-5x perf score'
            main_html_file.write('\n<th'+ ( ' title="'+v_tooltip+'"' if v_tooltip else '') +'>'+ h.replace('_',' ') +'</th>')


    ##############
    # output data:
    ##############
    # MAJOR_VERSIONS_LST = '6x,5x,4x'
    print('fields=',fields)
    print('ftypes=',ftypes)

    for report_row in data_in_descending_order:

        main_html_file.write('\n<tr>')

        fb_details_map = {}
        for fbv in [x.replace('"','') for x in fb_vers_cols]: # ['fb6x_vers', 'fb5x_vers', 'fb4x_vers'] etc
            fb_prefix = fbv.split('_')[0]+'_'
            if report_row[ fb_prefix+'vers' ]:
                # Extract report for this OLTP-EMUL run and store in DETLPATH
                # Returns name of this .html report:
                oltp_run_report_html = extract_detailed_report( con, report_row, fb_prefix, DETLPATH )

                # Extract stack traces for all crashes that occured during this run.
                # Return LIST of .html files with stack traces:
                oltp_run_stk_traces = extract_stack_traces( con, report_row, fb_prefix, DETLPATH )

                oltp_run_hhmm = report_row.get(fb_prefix+'run_hhmm', '') # tooltip: test phase, beg...end
                fb_details_map[ fbv ]  = (oltp_run_report_html, oltp_run_stk_traces, oltp_run_hhmm)

        print('chk fb_details_map:')
        for k,v in fb_details_map.items():
            print(k,':::',v)

        fb3x_run_id, fb3x_build_no, fb4x_run_id,fb4x_build_no, fb5x_run_id,fb5x_build_no = None,None, None,None, None,None
        fb3x_detl_file, fb4x_detl_file, fb5x_detl_file = None, None, None
        fb3x_detl_rows, fb4x_detl_rows, fb5x_detl_rows = {}, {}, {}

        col_idx=-1
        for fld_name in report_row:
            v_style=''
            cell_value = report_row[fld_name]
            col_idx += 1

            print('fld_name=',fld_name,'; col_idx=',col_idx,'; ftypes[col_idx]=',ftypes[col_idx])

            if fld_name.lower() == 'run_seqn' or fld_name.lower().endswith('run_id') or fld_name.lower().endswith('compress_cmd') or fld_name.lower().endswith('run_hhmm'):
                # do not show these values in the report
                ### NOP ###
                continue

            v_tooltip = ''
            if not report_row[fld_name]:
                cell_value = '[null]'
                v_style = ' class="null_cell"'
            else:

                #print('ftypes[col_idx]=',ftypes[col_idx] )
                #print('repr: ',repr( ftypes[col_idx] ))

                css_items = ''

                if fld_name.lower().endswith('vers'): # ==> 'fb3x_vers', 'fb4x_vers'

                    v_tooltip = fb_details_map.get(fld_name.lower(), ('',[],''))[2]
                    if v_tooltip:
                        v_tooltip = 'test time: ' + v_tooltip

                    detl_file_name = fb_details_map.get(fld_name.lower(), ('',[]))[0]
                    #print(f'{fld_name.lower()=}, {detl_file_name=}')
                    if detl_file_name:
                        cell_value = '<a style="text-decoration:none" href="' + DETLPREF + '/' +  os.path.split( detl_file_name )[1] + '" target="_blank"> '+ str(cell_value) +'</a>'

                elif fld_name.lower().endswith('perf_score'): # ==> 'fb3x_perf_score', 'fb4x_perf_score', 'fb5x_perf_score'
                    css_items += ' perf_score_column'
                elif repr( ftypes[col_idx] ) in ( "<class 'int'>", "<type 'long'>", "<type 'float'>", "<class 'float'>", "<class 'decimal.Decimal'>" ):
                    # do NOT use: cell_value = locale.format('%.0f', cell_value, grouping=True) -- converting to string problem here.
                    if repr( ftypes[col_idx] ) in ( "<class 'int'>", "<type 'long'>" ):
                        cell_value = '{:,d}'.format(cell_value).replace(',',' ')
                        css_items += ' big_numbers' # nowrap spaces!
                    else:
                        cell_value = '{:.2f}'.format(cell_value) # show memory consumption in Mb

                    if fld_name.lower().endswith(' mem, all'):          #  ==> 'fb3x_used_all', 'fb4x_used_all'
                        css_items += ' memo_used_whole_db_column'
                    elif fld_name.lower().endswith(' mem, att'):     # ==> 'fb3x_used_by_att', 'fb4x_used_by_att'
                        css_items += ' memo_used_att_level_column'
                    elif fld_name.lower().endswith(' mem, trn'):     # ==> 'fb3x_used_by_trn', 'fb4x_used_by_trn'
                        css_items += ' memo_used_trn_level_column'
                    elif fld_name.lower().endswith(' mem, stm'):     # ==> 'fb3x_used_by_stm', 'fb4x_used_by_stm'
                        css_items += ' memo_used_stm_level_column'

                elif fld_name.lower().endswith('result'): # ==> 'fb3x_outcome', 'fb4x_outcome', 'fb5x_outcome'

                    cell_value = cell_value.lower()
                    if 'crash' in cell_value:
                        css_items += ' fbx_outcome_crash'
                        # 19.12.2020: extract stack-traces (which were gathered during test finish
                        # for every dumps occured within time interval from test lunch to finish)
                        # to separate .html files and provide links to it.
                        stack_trace_html_files = []

                        fbvers_key = fld_name.lower().split('_')[0] + '_vers' # 'fb6x_vers'; 'fb5x_vers' etc
                        stack_trace_html_files = fb_details_map.get(fbvers_key, ('',[]))[1]

                        for s in stack_trace_html_files:
                            # Get name of file, extract from it part that points to timestamp of dump (in YYYYmmDD_HHMMSS.zzz form)
                            # and provide URL to this stack trace:

                            # Extract name of full path+file:
                            # /var/tmp/oltp_overall_report/details/oltp-crash-build_33400_run_3052_id_3329.20201219_094111.649.html
                            # ==> oltp-crash-build_33400_run_3052_id_3329.20201219_094111.649.html
                            stk_file_name = os.path.split( s )[1]
                            # Get timestamp of dump by extracting last 3 tokens and take first two of them:
                            #  oltp-cras***.20201219_094111.649.html ==> ['20201219_094111', '649'] ==> '20201219_094111.649'
                            dump_time_str = '.'.join( stk_file_name.split('.')[-3::][:2] )
                            dump_time_obj = datetime.datetime.strptime( dump_time_str, '%Y%m%d_%H%M%S.%f' )
                            # Convert to format dd.mm.YYYY HH:MM:SS.zzz
                            dump_time_url = dump_time_obj.strftime('%d.%m.%Y %H:%M:%S.%f')[:23]

                            cell_value += '\n<li><a style="text-decoration:none" href="' + DETLPREF + '/' + stk_file_name + '" target="_blank">' + dump_time_url +'</a></li>'

                    elif 'abnormal' in cell_value:
                        css_items += ' fbx_outcome_abend'
                    elif 'premature' in cell_value:
                        css_items += ' fbx_outcome_premature'
                    else:
                        v_tooltip = cell_value # "normal: test_time expired at 2023-04-08 16:42:29""
                        cell_value = 'normal'  # make content shorter, suggested by Vlad.
                        css_items += ' fbx_outcome_normal'

                # NB: several classes will be here:
                v_style = ' class="' + css_items +'"' if css_items else ''

            main_html_file.write('\n<td' + v_style + ( ' title="'+v_tooltip+'"' if v_tooltip else '') +  '>' + str(cell_value) + '</td>')

        main_html_file.write('\n</tr>')

    main_html_file.write('\n</table>')

    print(showtime(), 'Completed.')

    main_html_file.write('\n</body>\n</html>\n')

# < close con and html

print(showtime(), 'Final report see in: ' + main_html_file.name)
print(showtime(), 'Bye-bye from '+whoami)
