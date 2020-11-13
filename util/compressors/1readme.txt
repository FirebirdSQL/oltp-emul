Need only for WINDOWS.

This folder contains packed executables for making (de-)compression from/to 7-Zip and Z-Standard formats.
They are used in {OLTP_ROOT}\oltp-overall-report\oltp_overall_report.bat for extracting HTML reports
which preliminary were compressed, encoded to base64 format with further storing in the database which
name is defined by <results-storage-fbk> config of OLTP-EMUL test.
Compression of HTML report is performed in 'oltp_isql_run_worker' scenario after each test finish.

Extraction from .zip files will be done by %systemroot%\system32\cscript utility
(temporary .vbs script will be generated and applied every time).
