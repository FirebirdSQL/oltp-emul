This folder contains UDFs for running on 64-bit platforms.
Followind commands can be used to extract UDF files:
===
    1. Windows: 7zip -x -tzip .\SleepUDF.dll.zip 
    2. POSIX:   bzip2 -dk ./SleepUDF.so.bz2
===

Put extracted binary into any folder that can be accessed according to 'UDFaccess' parameter from firebird.conf. 
Usually this is 'UDF' sub-folder in Firebird home directory.
Please note that starting from Firebird 4.0 UDFaccess by default is 'None' rather than 'Restrict UDF' in previous versions.

You can skip the declaration and verifying whether UDF is correct and what input parameter means: seconds or milliseconds.
Test does it itself by running SQL script that is specified by config parameter 'sleep_ddl'.


Of course, you can use UDF in some other way, not only in this test.
Declaration:
===
    declare external function sleep
        integer
    returns integer by value
    entry_point 'SleepUDF' module_name 'SleepUDF';
    commit;
===
