WINDOWS ONLY.

This folder contains packed executables for making (de-)compression from/to 7-Zip and Z-Standard formats.
They are used in:
    1) {OLTP_ROOT}\src\oltp_isql_run_worker.bat
        This scenario compresses HTML report and converts it to base64 format with further storing
        in the dedicated database. This DB name is defined by config parameter <results_storage_fbk>;

    2) {OLTP_ROOT}\oltp-overall-report\oltp_overall_report.bat
       This scenario extracts from <results_storage_fbk> textual data in base64-format, runs decoding it
       to binary (.zip/.7z/.zst) and run decompression to readable HTML content.

When config parameter <report_compressor> is defined and points to 7-Zip or Z-Standard then apropriate
binary will be extracted from these .zip files. You do not have to install any of these packages first:
extraction will be done by %systemroot%\system32\cscript utility (by generating temporary .vbs script).
