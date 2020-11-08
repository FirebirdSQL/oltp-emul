from __future__ import print_function
import inspect
import os
import sys
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

# yum -y install python-pip
# pip install --upgrade pip
# pip install fdb

# This package allows to obtain .fbt into dict, see ast.literal_eval() call:
import ast

from shutil import copyfile
import datetime
import time
import fdb
try:
    # Py-3
    from urllib.parse import quote
except ImportError:
    from urllib import quote

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
            
            top.document.title = decodeURIComponent( (urlp['page_title']+'').replace(/\+/g, '%%20') );
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
    # fb_prefix = 'fb3x_', 'fb4x_'

    run_id = str(rec[ fb_prefix+'run_id'])
    build_no = rec[ fb_prefix+'vers'].split('.')[-1]

    if not rec[ fb_prefix + 'compress_cmd']:
        detl_ext = '.html'
    else:
        
        #print("rec[ fb_prefix+'compress_cmd' ]=",rec[ fb_prefix+'compress_cmd' ])

        if '/' in rec[ fb_prefix+'compress_cmd' ]:
            # /usr/bin/zip ; /usr/bin/7za ; /usr/bin/zstd
            compress_base = rec[ fb_prefix+'compress_cmd'].split('/')[-1].lower()
        else:
            # c:\...\7z.exe ; c:\...\zstd.exe etc
            compress_base = os.path.splitext(rec[ fb_prefix+'compress_cmd'].split('\\')[-1])[0].lower()
        
        #print('compress_base=',compress_base)

        if compress_base in ('7z', '7za'):
            detl_ext = '.7z'
        elif compress_base == 'zst':
            detl_ext = '.zst'
        else:
            detl_ext = '.zip'

        detl_ext += '.b64'
        #print('detl_ext=',detl_ext)
        #print('')

  
    # Extract report for this OLTP-EMUL run and store in html_path
    ################
    c_report = con.cursor()
    c_report.execute( 'select txt, zip2b64 from sp_show_report_data( ?, ?)', (build_no, run_id, ) )

    detl_rows=c_report.fetchallmap()
    c_report.close()

    html_file = None
    if detl_rows:
        file_pref = 'oltp-report_build_' +build_no + '_run_' + run_id
        detl_file = os.path.join(html_path, file_pref + detl_ext )
        html_file = os.path.join(html_path, file_pref + '.html')

        if not rec[ fb_prefix+'compress_cmd']:
            # field fbNN_compress_cmd is NULL --> output raw text from 'txt' field directly to .html-file
            f = codecs.open( detl_file, 'w', encoding='utf-8')
            for t in [ t for t in detl_rows if t['TXT'] ]:
                f.write( t['TXT'] + '\n' )
            f.close()
        else:
            # field fbNN_compress_cmd is NOT null --> output base64 data from 'zip2b64' field, then decode + decompress it to html
            f = codecs.open( detl_file, 'w')
            for t in [t for t in detl_rows if  t['ZIP2B64'] ]:
                f.write( t['ZIP2B64'] + '\n' )
            f.close()
            #print('created file ', f.name)
    
    # We return name of HTML file in order to have link to open it when click on some cell with performance value in the table:
    return html_file

# end of extract_detailed_report

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

    main_html_file.write( chart_script_beg )

# end of write_chart_script_beg

#-------------------------------------
def write_chart_data( main_html_file, chart_data, points_limit, fb3x_field_name, fb4x_field_name, values_fmt, values_descr ):
    i=0
    # values_descr = 'peak memory used by statements';
    for r in chart_data:
        if i==0:
            main_html_file.write("\n" + " "*12 + "[ '','FB3x %(values_descr)s', 'FB4x %(values_descr)s', ]"  % locals() )

        #fb3x_field_value, fb4x_field_value = 'null', 'null'
        fb3x_field_value, fb4x_field_value = '0',    '0'

        if r[fb3x_field_name]:
            fb3x_field_value = values_fmt.format( r[fb3x_field_name] )
        if r[fb4x_field_name]:
            fb4x_field_value = values_fmt.format( r[fb4x_field_name] )

        main_html_file.write( "\n" + " "*12 + ",[ '" +  r['run_date'].strftime("%d.%m.%y") + "', " + fb3x_field_value + "," + fb4x_field_value + "]" )
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

    # 05.10.2020
    chartAreaLeft = attrib_map.get( 'chartAreaLeft', DEFAULT_CHART_AREA_LEFT) # optional: value for 'chartArea{ left:NNN, ...}'; value must NOT be less than 100!
    chartAreaTop= attrib_map.get('chartAreaTop', DEFAULT_CHART_AREA_TOP) # optional:  value for 'chartArea{ ..., top:NNN}'; value must NOT be less than 20!

    chartAttr = "var chart = new google.visualization.%(chartType)s( document.getElementById('%(divname)s') );" % locals()
    colorAttr = "colors: " + str(colorList).strip('()') + ","
    curveAttr = "curveType: '%(curveType)s'," % locals() if curveType else ''

    # 19.08.2020: added 'chartArea:{left:N, top:M}'in order to adjust chart to the left margin of page.
    # NB do not set 'left' in chartArea less than 100 otherwise number on vertical axis will be hidden.
    chart_script_end=\
    '''
        ]);
        new google.visualization.NumberFormat({ pattern:'0' }).format(data, 1);
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

MAX_ROWS_IN_REPORT=int(os.environ['MAX_ROWS_IN_REPORT'])
MAX_POINTS_IN_CHART=int(os.environ['MAX_POINTS_IN_CHART'])

# Default values for width and height of areas for charts drawing.
# Used for assigning to divWidth and divHeight in write_chart_script_beg()
DEFAULT_CHART_DIV_WIDTH=int(os.environ['DEFAULT_CHART_DIV_WIDTH'])
DEFAULT_CHART_DIV_HEIGHT=int(os.environ['DEFAULT_CHART_DIV_HEIGHT'])

DEFAULT_CHART_AREA_LEFT=int(os.environ['DEFAULT_CHART_AREA_LEFT'])
DEFAULT_CHART_AREA_TOP=int(os.environ['DEFAULT_CHART_AREA_TOP'])

MAIN_RPT_FILE=os.environ['MAIN_RPT_FILE']

#######################################

con = fdb.connect( dsn = 'localhost:'+DB_NAME, user = DB_USER, password = DB_PSWD, fb_library_name = FB_CLNT, no_gc=1, no_db_triggers=1, no_linger=1, charset='utf8')
print(showtime(), con.firebird_version )

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

stm=\
'''
    select
        "run_date"
        ,"run_seqn"
        ,"fb3x_vers"
        ,"fb4x_vers"
        ,"fb3x_perf_score"
        ,"fb4x_perf_score"
        ,"fb3x_used_all"
        ,"fb4x_used_all"
        ,"fb3x_used_by_att"
        ,"fb4x_used_by_att"
        ,"fb3x_used_by_trn"
        ,"fb4x_used_by_trn"
        ,"fb3x_used_by_stm"
        ,"fb4x_used_by_stm"
        ,"fb3x_run_hhmm"
        ,"fb4x_run_hhmm"
        ,"fb3x_outcome"
        ,"fb4x_outcome"
        ,"fb3x_run_id"
        ,"fb4x_run_id"
        ,"fb3x_compress_cmd"
        ,"fb4x_compress_cmd"
    from sp_show_results(%(MAX_POINTS_IN_CHART)s) -- returns data in order: run_date desc, run_seqn asc
''' % locals()

#if MAX_ROWS_IN_REPORT > 0:
#    stm += ' rows ' + str( MAX_ROWS_IN_REPORT )

perf_score_hint='number of successfully completed business actions per minute, average for <test_time> interval'
memo_used_hint='maximal value of mon$memory_usage.mon$memory_used during <test_time> interval'

col_hints={
        "run_date" : "date of test run"
        ,"run_seqn" : "sequential number of this launch within date"
        ,"fb3x_vers" : "FB 3.x snapshot version"
        ,"fb4x_vers" : "FB 4.x snapshot version"
        ,"fb3x_perf_score" : "FB 3.x, %(perf_score_hint)s" % locals()
        ,"fb4x_perf_score" : "FB 4.x, %(perf_score_hint)s" % locals()
        ,"fb3x_used_all" : "FB 3.x, %(memo_used_hint)s, for DB level" % locals()
        ,"fb4x_used_all"  : "FB 4.x, %(memo_used_hint)s, for DB level" % locals()
        ,"fb3x_used_by_att" : "FB 3.x, %(memo_used_hint)s, for ATTACHMENT level" % locals()
        ,"fb4x_used_by_att" : "FB 4.x, %(memo_used_hint)s, for ATTACHMENT level" % locals()
        ,"fb3x_used_by_trn" : "FB 3.x, %(memo_used_hint)s, for TRANSACTION level" % locals()
        ,"fb4x_used_by_trn" : "FB 4.x, %(memo_used_hint)s, for TRANSACTION level" % locals()
        ,"fb3x_used_by_stm" : "FB 3.x, %(memo_used_hint)s, for STATEMENT level" % locals()
        ,"fb4x_used_by_stm" : "FB 4.x, %(memo_used_hint)s, for STATEMENT level" % locals()
        ,"fb3x_run_hhmm" : "FB 3.x, start of phase defined by <test_time> minutes"
        ,"fb4x_run_hhmm" : "FB 3.x, start of phase defined by <test_time> minutes"
        ,"fb3x_outcome" : "FB 3.x, outcome of test"
        ,"fb4x_outcome" : "FB 3.x, outcome of test"
}

cur= con.cursor()
cur.execute(stm)

col=cur.description
fields = [c[0] for c in col]
ftypes = [c[1] for c in col]

#fields= ['run_date', 'fb3x_vers', 'fb4x_vers', 'fb3x_perf_score', 'fb4x_perf_score', 'fb3x_used_all', 'fb4x_used_all', 'fb3x_used_by_att', 'fb4x_used_by_att', 'fb3x_used_by_trn', 'fb4x_used_by_trn', 'fb3x_used_by_stm','fb4x_used_by_stm', 'fb3x_run_hhmm', 'fb4x_run_hhmm', 'fb3x_outcome', 'fb4x_outcome']
#ftypes= [<type 'datetime.date'>, <type 'str'>, <type 'str'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'long'>, <type 'str'>, <type 'str'>, <type 'str'>, <type 'str'>]

print(showtime(), 'Gather data from sp_show_results...' )

#################################
###  f e t c h  a l l  m a p  ###
#################################
data_in_descending_order=cur.fetchallmap()
cur.close()

print(showtime(), 'Completed. Number of records: ' + str(len(data_in_descending_order)) )

# Change order of data: we have to show charts in CHRONOLOGICAL order:
data_in_chronological_order = sorted(data_in_descending_order, key=lambda x: ( x['run_date'], -x['run_seqn'] ) )

#print('fields=',fields)
#print('ftypes=',ftypes)
#print('data_in_descending_order=',data_in_descending_order)
#for d in data_in_descending_order:
#    print(d)
#exit(0)

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
        'divName' : 'perf_total_chart_div'
        ,'drawFunc' : 'perf_total_chart'
    }
)

#        ,'legends'  : "['', 'FB 3.x performance score', 'FB 4.x performance score']"

# Output data for chart:
# ----------------------
write_chart_data( main_html_file, data_in_chronological_order, MAX_POINTS_IN_CHART, 'fb3x_perf_score', 'fb4x_perf_score', "{:9g}", 'performance score' )


# Output tail for chart script:
# ------------------------------
chart_script_end = write_chart_script_end(
    main_html_file, 
    {
        'colors': ['MediumVioletRed','Blue',],
        'curveType': 'function',
        'chartType': 'LineChart',
        'divName' : 'perf_total_chart_div'

    }
)

print(showtime(), 'Completed.' )
################################

#+-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-+

print(showtime(), 'Output CHART: memo_used, whole DB')
######################################################

main_html_file.write( '<h4> <a name="memo_used_all_chart">Memory usage: peak values of mon$memory_used for DB level</a> </h4>' )

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
write_chart_data( main_html_file, data_in_chronological_order, MAX_POINTS_IN_CHART, 'fb3x_used_all', 'fb4x_used_all', "{:20d}", 'peak memory used for DB level' )


# Output tail for chart script:
# ------------------------------
chart_script_end = write_chart_script_end(
    main_html_file, 
    { 
        'colors': ['SandyBrown','Sienna',],
        'curveType': 'function',
        'chartType': 'LineChart',
        'divName' : 'perf_memo_used_all_div'
      
    }   
)

print(showtime(), 'Completed.' )


#+-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-+

print(showtime(), 'Output CHART: memo_used, ATTACHMENTS level')
##############################################################

main_html_file.write( '<h4> <a name="memo_used_att_chart">Memory usage: peak values of mon$memory_used for attachments</a> </h4>' )

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
write_chart_data( main_html_file, data_in_chronological_order, MAX_POINTS_IN_CHART, 'fb3x_used_by_att', 'fb4x_used_by_att', "{:20d}", 'peak memory used by attachments' )


# Output tail for chart script:
# ------------------------------
chart_script_end = write_chart_script_end(
    main_html_file, 
    { 
        'colors': ['SkyBlue','SteelBlue',],
        'curveType': 'function',
        'chartType': 'LineChart',
        'divName' : 'perf_memo_used_att_div'
      
    }   
)

print(showtime(), 'Copmpleted.')

#+-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-+

print(showtime(), 'Output CHART: memo_used, TRANSACTIONS level')
################################################################

main_html_file.write( '<h4> <a name="memo_used_trn_chart">Memory usage: peak values of mon$memory_used for transactions</a> </h4>' )

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
write_chart_data( main_html_file, data_in_chronological_order, MAX_POINTS_IN_CHART, 'fb3x_used_by_trn', 'fb4x_used_by_trn', "{:20d}", 'peak memory used by transactions' )


# Output tail for chart script:
# ------------------------------
chart_script_end = write_chart_script_end(
    main_html_file, 
    { 
        'colors': ['LightGreen','SeaGreen',],
        'chartType': 'ScatterChart',
        'divName' : 'perf_memo_used_trn_div'
      
    }   
)

print(showtime(), 'Completed.')

#+-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-++-+-+-+-+-+

print(showtime(), 'Output CHART: memo_used, STATEMENTS level')
##############################################################

main_html_file.write( '<h4> <a name="memo_used_stm_chart">Memory usage: peak values of mon$memory_used for statements</a> </h4>' )

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
write_chart_data( main_html_file, data_in_chronological_order, MAX_POINTS_IN_CHART, 'fb3x_used_by_stm', 'fb4x_used_by_stm', "{:20d}", 'peak memory used by statements' )


# Output tail for chart script:
# ------------------------------
chart_script_end = write_chart_script_end(
    main_html_file, 
    { 
        'colors': ['Salmon','Purple',],
        'curveType': 'function',
        'chartType': 'LineChart',
        'divName' : 'perf_memo_used_stm_div'
      
    }   
)

print(showtime(), 'Completed.')


###############
# Output TABLE:
###############

print(showtime(), 'Output TABLE with results.')
################################################

main_html_file.write( '<h4> <a name="overall_results_table">All results in one table. Click on FB snapshot number to see detailed report for each run.</a> </h4>' )

main_html_file.write('\n<table class="t_table">')

# output column titles:
for h in fields:
    v_tooltip = col_hints.get(h)

    if h.lower() == 'run_seqn' or h.lower().endswith('run_id') or h.lower().endswith('compress_cmd'):
        ### NOP ###
        continue

    if h.lower().endswith('run_hhmm'):
        h = h.replace('run_hhmm', 'run hh:mm')

    # Output column title and its hint:
    main_html_file.write('\n<th'+ ( ' title="'+v_tooltip+'"' if v_tooltip else '') +'>'+ h.replace('_',' ') +'</th>')

for r in data_in_descending_order:
    main_html_file.write('\n<tr>')

    fb3x_run_id, fb3x_build_no, fb4x_run_id,fb4x_build_no = None,None, None,None
    fb3x_detl_file, fb4x_detl_file = None, None
    fb3x_detl_rows, fb4x_detl_rows = {}, {}
    if r['fb3x_vers']:

        # Extract report for this OLTP-EMUL run and store in DETLPATH
        fb3x_html_file = extract_detailed_report( con, r, 'fb3x_', DETLPATH )

    if r['fb4x_vers']:

        # Extract report for this OLTP-EMUL run and store in DETLPATH
        fb4x_html_file = extract_detailed_report( con, r, 'fb4x_', DETLPATH )

    col_idx=-1
    for f in r:
        v_style=''
        v = r[f]
        col_idx += 1
 
        # print('f=',f,'; col_idx=',col_idx,'; ftypes[col_idx]=',ftypes[col_idx])

        if f.lower() == 'run_seqn' or f.lower().endswith('run_id') or f.lower().endswith('compress_cmd'):
            ### NOP ###
            continue
        if not r[f]:
            v = '[null]'
            v_style = ' class="null_cell"'
        else:
            c_list = 'fb3x_font' if f.lower().startswith('fb3x') else ( 'fb4x_font' if f.lower().startswith('fb4x') else  '')

            if f.lower().endswith('vers'): # ==> 'fb3x_vers', 'fb4x_vers'

                detl_file_name = fb3x_html_file if f.lower().startswith('fb3x') else fb4x_html_file

                #print('detl_file_name=',detl_file_name)
                if detl_file_name and ( f.lower().startswith('fb3x') or f.lower().startswith('fb4x') ):
                
                    v = '<a style="text-decoration:none" href="' + DETLPREF + '/' +  os.path.split( detl_file_name )[1] + '" target="_blank"> '+ str(v) +'</a>'
                
            elif f.lower().endswith('perf_score'): # ==> 'fb3x_perf_score', 'fb4x_perf_score'
                c_list += ' perf_score_column'

            elif repr( ftypes[col_idx] ) in ( "<class 'int'>", "<type 'long'>" ):
                # do NOT use: v = locale.format('%.0f', v, grouping=True) -- converting to string problem here.
                v = '{:,d}'.format(v).replace(',',' ')
                c_list += ' big_numbers' # nowrap spaces!

                if f.lower().endswith('used_all'):          #  ==> 'fb3x_used_all', 'fb4x_used_all'
                    c_list += ' memo_used_whole_db_column'
                elif f.lower().endswith('used_by_att'):     # ==> 'fb3x_used_by_att', 'fb4x_used_by_att'
                    c_list += ' memo_used_att_level_column'
                elif f.lower().endswith('used_by_trn'):     # ==> 'fb3x_used_by_trn', 'fb4x_used_by_trn'
                    c_list += ' memo_used_trn_level_column'
                elif f.lower().endswith('used_by_stm'):     # ==> 'fb3x_used_by_stm', 'fb4x_used_by_stm'
                    c_list += ' memo_used_stm_level_column'

            elif f.lower().endswith('outcome'): # ==> 'fb3x_outcome', 'fb4x_outcome'

                v = v.lower()
                if 'crash' in v:
                    c_list += ' fbx_outcome_crash'
                elif 'abnormal' in v:
                    c_list += ' fbx_outcome_abend'
                elif 'premature' in v:
                    c_list += ' fbx_outcome_premature'
                else:
                    c_list += ' fbx_outcome_normal'

            # NB: several classes will be here:
            v_style = ' class="' + c_list +'"' if c_list else ''

        main_html_file.write('\n<td' + v_style + '>' + str(v) + '</td>')

    main_html_file.write('\n</tr>')

main_html_file.write('\n</table>')

print(showtime(), 'Completed.')

main_html_file.write('\n</body>\n</html>\n')
main_html_file.close()

print(showtime(), 'Closing connection to overall results DB.')
con.close()

print(showtime(), 'Final report see in: ' + main_html_file.name)
print(showtime(), 'Bye-bye from '+whoami)


