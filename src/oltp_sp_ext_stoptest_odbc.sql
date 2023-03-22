-- This is code that can be used to check ability to establish connection using ODBC plugin.
-- Name of this file must be assigned to the value of 'use_external_to_stop' parameter in OLTP-EMUL config.
-- This file must contain definition of stored procedure 'sp_ext_stoptest'with output parameter 'need_to_stop' of type smallint.
-- This SP must not depend on any ÂÈ objects. Only one object must depend on this procedure: V_STOPTEST.
-- One need to be sure that:
-- 1. firebird.conf contains 'ODBCEngine' in the list of providers, e.g.:
--   Providers = Remote,Engine13,ODBCEngine,Loopback
-- 2. folder %FB_HOME%\plugins\ contrains library ODBCEngine.dll
-- 3. ODBC data sources contain appropriate entry
-- 4. Target database is online and has table with name 'stoptest' with one column of any type and at least one row.
--    Name of host, port, database, user and password must be adjusted here if this is needed.
-- #######################################################################
set term ^;
create or alter procedure sp_ext_stoptest returns (need_to_stop smallint)
as
    declare dsn varchar(255) = ':odbc:DRIVER={MariaDB ODBC 3.1 Driver};SERVER=192.168.1.67;PORT=3306;DATABASE=employees;TCPIP=1;CHARSET=utf8mb4;UID=root';
    declare psw varchar(20) = 'sa';
begin
    -- /*
    -- MySQL table:
    -- create table conn_audit(id int primary key auto_increment, mysql_conn_id int default connection_id(), fb_conn_id int, fb_whoami varchar(32), fb_dts datetime(3), mysql_dts datetime(3) default current_timestamp);
    in autonomous transaction do
    execute statement ( q'{insert into conn_audit(fb_conn_id, fb_whoami, fb_dts) values(?, ?, ?)}' ) (current_connection, current_user, cast('now' as timestamp))
    on external dsn
    as user null password psw
    ;
    -- */
    ----------------------------
    need_to_stop = null;
    execute statement 'select id from stoptest limit 1'
        on external dsn
        as user null password psw
    into need_to_stop;
    if (need_to_stop is not null) then
        suspend;
end
^
set term ;^
commit;
