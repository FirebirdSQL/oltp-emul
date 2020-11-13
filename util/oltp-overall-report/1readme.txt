This directory contains two scripts (oltp_overall_report.bat; oltp_overall_report.sh) for generating report
that contains results of every previous OLTP-EMUL runs, for both FB 3.x and 4.x.
Firebird 4.x must present to make overall report with OLTP-EMUL results.

It is reasonably to start these scripts by scheduler, when OLTP-EMUL not running.

Python 3.4+ required.
Python package 'fdb' must be installed first (e.g., you can run: 'pip instll fdb' to install it).

Script will search oltpNN_config for BOTH major versions of Firebird: 3.x and 4.x.
Both configs must contain parameter <results_storage_fbk> which points to backup of auxiliary database that
is created by OLTP-EMUL (if needed) and is fulfilled with results of test after its finish.
Because of this, you have to run at least one time OLTP-EMUL for *every* of major FB versions, 3.x and 4.x.

Both files specified by <results_storage_fbk> will be restored to temprary databases.
Further script will create auxiliary database (if it was not created before) and run ES/EDS statements from
<results_storage_NN> to this database in order to accumulate results.

After this, HTML-report will be created by Python script 'oltp_overall_report.py': it will connect to database
with overall results using 'fdb' driver and obtain necessary data from it.

Final report will be created in the folder defined by parameter <LOGDIR> (see 'oltp_overall_report_config.*').
Report is HTML file with path and name defined by parameter <MAIN_RPT_FILE>.
In the same folder file <reportname>.css will be stored for correct display of report content.
Sub-folder with name 'DETAILS' will be created forstoring results of every test run, also in HTML format.

These results can be compressed and uploaded to some http or ftp server.
Compressor 7-Zip is used for this. On Linux it must be already installed first.
For Linux uploading task was implemented only for HTTP server, see config SSH_* parameters.
For Windows this script can only upload results to ftp server, see config FTP_* parameters (not tested deep).
