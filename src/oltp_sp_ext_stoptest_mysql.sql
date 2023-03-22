-- This is code that can be used to check ability to establish connection to MySQL database.
-- Name of this file must be assigned to the value of 'use_external_to_stop' parameter in OLTP-EMUL config.
-- This file must contain definition of stored procedure 'sp_ext_stoptest'with output parameter 'need_to_stop' of type smallint.
-- This SP must not depend on any ÂÈ objects. Only one object must depend on this procedure: V_STOPTEST.
-- One need to be sure that:
-- 1. firebird.conf contains 'MySQLEngine' in the list of providers, e.g.:
--   Providers = Remote,Engine13,MySQLEngine,Loopback
-- 2. folder %FB_HOME%\plugins\ contrains library MySQLEngine.dll
-- 3. folder %FB_HOME% contains libraries: libmariadb.dll, caching_sha2_password.dll and auth_gssapi_client.dll
-- 4. MySQL database is online and has table with name 'stoptest' with one column of any type and at least one row.
--    Name of MySQL host, port, database, user and password must be adjusted here if this is needed.
-- #######################################################################
set term ^;
create or alter procedure sp_ext_stoptest returns (need_to_stop smallint)
as
    declare dsn varchar(255) = ':mysql:host=192.168.1.67;port=3306;database=employees;user=root';
    declare psw varchar(20) = 'sa';
begin
    /*
    -- MySQL table:
    -- create table conn_audit(id int primary key auto_increment, mysql_conn_id int default connection_id(), fb_conn_id int, fb_whoami varchar(32), fb_dts datetime(3), mysql_dts datetime(3) default current_timestamp);
    in autonomous transaction do
    execute statement ( q'{insert into conn_audit(fb_conn_id, fb_whoami, fb_dts) values(?, ?, ?)}' ) (current_connection, current_user, cast('now' as timestamp))
    on external dsn
    as user null password psw
    ;
    */
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
