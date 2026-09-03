REM Oracle Data Collection Script
REM Version: 2.0
REM
REM Version 2.0 Updates (2026-09-03):
REM - Output field delimiter changed from comma to a tab character (chr(9)); some collected
REM   values (e.g. LogArchiveConfig, patchLevel) can legitimately contain commas.
REM - Added SET DEFINE OFF so an "&" in a collected value is not treated as a SQL*Plus
REM   substitution-variable prompt.
REM - dbSizeTB, allocated_dbSizeTB, encryptedDataSizeTB, dailyRedoSizeTB (previously
REM   dbSizeMB/allocated_dbSizeMB/encryptedDataSizeMB/dailyRedoSize) now report TB with
REM   6 decimal places instead of MB/bytes.
REM - biggestBigfileGB, bigfileDataSizeGB (previously *MB) now report GB with 6 decimal places.
REM - sgaMaxSizeGB, sgaTargetGB, pgaAggregateTargetGB, physMemoryGB (previously without the
REM   GB suffix) now report GB at full precision instead of raw bytes.
REM - dbSizeTB and allocated_dbSizeTB now coalesce to 0 instead of returning blank for
REM   containers with no visible segments or datafiles, such as PDB$SEED.

-- connect to the system schema
--conn SYSTEM@$1

-- create private temporary table to hold all  collected

create global temporary table rubrikDataCollection
	(
	con_id number,
	conName varchar2(128),
	dbSizeTB number,
	allocated_dbSizeTB number,
	biggestBigfileGB number,
	dailyChangeRate number,
	dailyRedoSizeTB number,	
	datafileCount number,		
	hostName varchar2(64),
	instName varchar2(16),
	dbVersion varchar2(17),
--	dbEdition varchar2(7),
-- updating dbEdition to support larger entries in v$instance.version
	dbEdition varchar2(100),
	platformName varchar2(101),
	dbName varchar2(9),
	dbUniqueName varchar2(30),
	dbID varchar2(200),
	flashbackEnabled varchar2(18),
	archiveLogEnabled varchar2(12),
	spfile varchar2(200),
	patchLevel varchar2(100),
	cpuCount number,
	blockSize number,
	racEnabled varchar2(20),
	sgaMaxSizeGB number,
	sgaTargetGB number,
	pgaAggregateTargetGB number,
	physMemoryGB number,
	dNFSenabled varchar2(20),
	GoldenGate varchar2(20),
	exadataEnabled varchar2(20),
	bctEnabled varchar2(20),
	LogArchiveConfig varchar2(200),
	ArchiveLagTarget number,
	tablespaceCount number,
	encryptedTablespaceCount number,
	encryptedDataSizeTB number,
	bigfileTablespaceCount number,
	bigfileDataSizeGB number,
	logfileCount number,
	tempfileCount number
	)
on commit preserve rows;

insert into rubrikDataCollection
(
con_id,
conName,
hostName,
instName,
dbVersion,
dbEdition,
platformName,
dbName,
dbUniqueName,
dbID,
flashbackEnabled,
archiveLogEnabled
)
select cont.con_id,
cont.name,
inst.host_name,
inst.instance_name,
inst.version,
inst.edition,
db.platform_name,
db.name,
db.db_unique_name,
cont.dbid,
db.flashback_on,
db.log_mode
from v$instance inst,
v$database db,
v$containers cont
/

UPDATE rubrikDataCollection rbk
SET spfile = (select decode(count(*), 0, 'NO', 'YES') from v$parameter where name='spfile')
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance);

-- result is the latest patch
UPDATE rubrikDataCollection rbk
SET patchLevel = (select * from (select description from dba_registry_sqlpatch order by ACTION_TIME desc) where ROWNUM = 1)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance);

UPDATE rubrikDataCollection rbk
SET cpuCount = (SELECT value from v$parameter where name='cpu_count')
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance);

UPDATE rubrikDataCollection rbk
SET blockSize = (SELECT value from v$parameter where name='db_block_size')
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance);

UPDATE rubrikDataCollection rbk
SET racEnabled = (SELECT value from v$parameter where name='cluster_database')
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance);

UPDATE rubrikDataCollection rbk
SET sgaMaxSizeGB = (SELECT value/1024/1024/1024 from v$parameter where name='sga_max_size')
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance);

UPDATE rubrikDataCollection rbk
SET sgaTargetGB = (SELECT value/1024/1024/1024 from v$parameter where name='sga_target')
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance);

UPDATE rubrikDataCollection rbk
SET pgaAggregateTargetGB = (SELECT value/1024/1024/1024 from v$parameter where name='pga_aggregate_target')
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance);

UPDATE rubrikDataCollection rbk
SET physMemoryGB = (SELECT max(value)/1024/1024/1024 from dba_hist_osstat where stat_name = 'PHYSICAL_MEMORY_BYTES')
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance);

UPDATE rubrikDataCollection rbk
SET dNFSenabled = (select decode(count(*), 0, 'NO', 'YES') from v$dnfs_servers)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance);

-- v$datafile is container-aware
UPDATE rubrikDataCollection rbk
SET dbSizeTB = (select round(sum(bytes)/1024/1024/1024/1024,6) bytes from dba_segments where con_id=rbk.con_id group by con_id)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and con_id=rbk.con_id;

UPDATE rubrikDataCollection rbk
SET allocated_dbSizeTB = (select round(sum(bytes)/1024/1024/1024/1024,6) bytes from v$datafile where con_id=rbk.con_id group by con_id)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and con_id=rbk.con_id;

UPDATE rubrikDataCollection rbk
SET dbSizeTB = 0
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and dbSizeTB is null;

UPDATE rubrikDataCollection rbk
SET allocated_dbSizeTB = 0
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and allocated_dbSizeTB is null;


-- v$archive_dest is container-aware
-- if cont_id is 0, it means the entire CDB
UPDATE rubrikDataCollection rbk
SET GoldenGate = (select decode(count(*), 0, 'NO', 'YES') from v$archive_dest where status = 'VALID' and target = 'STANDBY' and con_id=0)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance);

UPDATE rubrikDataCollection rbk
SET GoldenGate = (select decode(count(*), 0, 'NO', 'YES') from v$archive_dest where status = 'VALID' and target = 'STANDBY' and con_id=rbk.con_id)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and con_id=rbk.con_id;

-- gv$cell is container-aware 
-- if cont_id is 0, it means the entire CDB
UPDATE rubrikDataCollection rbk
SET exadataEnabled = (select decode(count(*), 0, 'NO', 'YES') from v$cell where con_id=0)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance);

UPDATE rubrikDataCollection rbk
SET exadataEnabled = (select decode(count(*), 0, 'NO', 'YES') from v$cell where con_id=rbk.con_id)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and con_id=rbk.con_id;

-- v$block_change_tracking is container-aware
-- for now, BCT is allowed only in CDB
UPDATE rubrikDataCollection rbk
SET bctEnabled = (select status from v$block_change_tracking)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance);

UPDATE rubrikDataCollection rbk
SET LogArchiveConfig = (SELECT value from v$parameter where name='log_archive_config')
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance);

UPDATE rubrikDataCollection rbk
SET LogArchiveConfig = 'NO'
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and LogArchiveConfig is null;

UPDATE rubrikDataCollection rbk
SET ArchiveLagTarget = (SELECT value from v$parameter where name='archive_lag_target')
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance);	

-- v$tablespace is container-aware
UPDATE rubrikDataCollection rbk
SET tablespaceCount = (select count(*)  from v$tablespace where con_id=rbk.con_id group by con_id)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and con_id=rbk.con_id;

-- containers clause works on dba_tablespaces 
UPDATE rubrikDataCollection rbk
SET encryptedTablespaceCount = (select count(*) from containers(dba_tablespaces) where encrypted='YES' and con_id=rbk.con_id)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and con_id=rbk.con_id;

-- containers clause works on dba_data_files and dba_tablespaces
UPDATE rubrikDataCollection rbk
SET encryptedDataSizeTB = (select round(sum(bytes)/1024/1024/1024/1024,6) from (select dbf.con_id,sum(bytes) bytes from containers(dba_data_files) dbf, containers(dba_tablespaces) tbsp where dbf.tablespace_name=tbsp.tablespace_name and dbf.con_id=tbsp.con_id and tbsp.encrypted='YES' group by dbf.con_id) where con_id=rbk.con_id)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and con_id=rbk.con_id;

UPDATE rubrikDataCollection rbk
SET encryptedDataSizeTB = 0
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and encryptedDataSizeTB is null;

UPDATE rubrikDataCollection rbk
SET bigfileTablespaceCount = (select count(*) from containers(dba_tablespaces) where bigfile='YES' and con_id=rbk.con_id)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and con_id=rbk.con_id;

-- containers clause works on dba_data_files and dba_tablespaces
UPDATE rubrikDataCollection rbk
SET biggestBigfileGB = (select round(sum(bytes)/1024/1024/1024,6) from (select dbf.con_id, max(bytes) bytes from containers(dba_data_files) dbf, containers(dba_tablespaces) tbsp where dbf.tablespace_name=tbsp.tablespace_name and dbf.con_id=tbsp.con_id and tbsp.bigfile='YES' group by dbf.con_id) where con_id=rbk.con_id)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and con_id=rbk.con_id;

UPDATE rubrikDataCollection rbk
SET biggestBigfileGB = 0
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and biggestBigfileGB is null;

UPDATE rubrikDataCollection rbk
SET bigfileDataSizeGB = (select round(sum(bytes)/1024/1024/1024,6) from (select dbf.con_id, sum(bytes) bytes from containers(dba_data_files) dbf, containers(dba_tablespaces) tbsp where dbf.tablespace_name=tbsp.tablespace_name and dbf.con_id=tbsp.con_id and tbsp.bigfile='YES' group by dbf.con_id) where con_id=rbk.con_id)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and con_id=rbk.con_id;

UPDATE rubrikDataCollection rbk
SET bigfileDataSizeGB = 0
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and bigfileDataSizeGB is null;

-- v$datafile and v$archived_log are container-aware (no need for container clause)
-- 20220310 smcelhinney removing division by 100 from dailyChangeRate as it negatively skews change rate
UPDATE rubrikDataCollection rbk
SET dailyChangeRate = (select dailyChangeRate from (select dbf.con_id, round((avg(redo_size)/sum(dbf.bytes)),8) dailyChangeRate from containers(v$datafile) dbf, (select con_id, trunc(completion_time) rundate, sum(blocks*block_size) redo_size from containers(v$archived_log) where first_time > sysdate - 7 group by trunc(completion_time), con_id) group by dbf.con_id) where con_id=rbk.con_id)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and con_id=rbk.con_id;

-- v$datafile is container-aware (no need for container clause)
UPDATE rubrikDataCollection rbk
SET datafileCount = (select count(*) from v$datafile where con_id=rbk.con_id group by con_id)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and con_id=rbk.con_id;

-- v$logfile is container-aware (no need for container clause)
UPDATE rubrikDataCollection rbk
SET logfileCount = (select count(*) from v$logfile where con_id=rbk.con_id group by con_id)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and con_id=rbk.con_id;

-- as Multitenant instance won't have con_id=0, the result will be add into the root container (con_id=1)
UPDATE rubrikDataCollection rbk
SET logfileCount = (SELECT  SUM(total)
FROM   ( 
            select count(*) total from v$logfile where con_id=0
            UNION ALL
            select count(*) total from v$logfile where con_id=1
        ))
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and rbk.con_id=1;

UPDATE rubrikDataCollection rbk
SET logfileCount = 0
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and logfileCount is null;

-- v$tempfile is container-aware (no need for container clause)
UPDATE rubrikDataCollection rbk
SET tempfileCount = (select count(*) from v$tempfile where con_id=rbk.con_id group by con_id)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and con_id=rbk.con_id;

-- as Multitenant instance won't have con_id=0, the result will be add into the root container (con_id=1)
UPDATE rubrikDataCollection rbk
SET tempfileCount = (SELECT  SUM(total)
FROM   ( 
            select count(*) total from v$tempfile where con_id=0
            UNION ALL
            select count(*) total from v$tempfile where con_id=1
        ))
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and rbk.con_id=1;

UPDATE rubrikDataCollection rbk
SET tempfileCount = 0
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and tempfileCount is null;

-- v$archived_log is container-aware (no need for container clause)
UPDATE rubrikDataCollection rbk
SET dailyRedoSizeTB = (select round(dailyRedoSizeTB/1024/1024/1024/1024,6) from (select con_id, avg(redo_size) dailyRedoSizeTB from (select con_id, trunc(completion_time) rundate, sum(blocks*block_size) redo_size from v$archived_log where first_time > sysdate - 7 group by trunc(completion_time), con_id) group by con_id) where con_id=rbk.con_id)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and con_id=rbk.con_id;

-- as Multitenant instance won't have con_id=0, the result will be add into the root container (con_id=1)
UPDATE rubrikDataCollection rbk
SET dailyRedoSizeTB = (select round(dailyRedoSizeTB/1024/1024/1024/1024,6) from (select con_id, avg(redo_size) dailyRedoSizeTB from (select con_id, trunc(completion_time) rundate, sum(blocks*block_size) redo_size from v$archived_log where first_time > sysdate - 7 group by trunc(completion_time), con_id) group by con_id) where con_id=0)
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and rbk.con_id=1;

UPDATE rubrikDataCollection rbk
SET dailyRedoSizeTB = 0
WHERE instName = (select instance_name from v$instance)
and hostName= (select host_name from v$instance)
and dailyRedoSizeTB is null;

-- update temp table with con_name for recorded con_id
update rubrikDataCollection rbk set con_id=0 where con_id is null;
-- update root container and pdb seed names to include cdb database name
update rubrikDataCollection rbk set conName=(select name ||'.CDB$ROOT'from v$database) where conName='CDB$ROOT';
update rubrikDataCollection rbk set conName=(select name ||'.PDB$SEED'from v$database) where conName='PDB$SEED';
-- update remaining pdbs to append CDB name so pdb/cdb relationships are not lost in the csv
update rubrikDataCollection rbk set conName=(select name ||'.' from v$database)||conName where con_id>2;

commit;

-- format data collected for csv output
--set markup csv on
set linesize 32000
set define off
set headsep off
set head off
set trimspool on
set trimout on
set feedback off
set pagesize 0
set wrap off

spool rbkDiscovery.csv append

-- select * from rubrikDataCollection;

select con_id ||chr(9)||
	conName ||chr(9)||
	dbSizeTB ||chr(9)||
	allocated_dbSizeTB ||chr(9)||
        biggestBigfileGB ||chr(9)||
        dailyChangeRate ||chr(9)||
        dailyRedoSizeTB ||chr(9)||
        datafileCount ||chr(9)||
        hostName ||chr(9)||
        instName ||chr(9)||
        dbVersion ||chr(9)||
        dbEdition ||chr(9)||
        platformName ||chr(9)||
        dbName ||chr(9)||
        dbUniqueName ||chr(9)||
        dbID ||chr(9)||
        flashbackEnabled ||chr(9)||
        archiveLogEnabled ||chr(9)||
        spfile ||chr(9)||
        patchLevel ||chr(9)||
        cpuCount ||chr(9)||
        blockSize ||chr(9)||
        racEnabled ||chr(9)||
        sgaMaxSizeGB ||chr(9)||
        sgaTargetGB ||chr(9)||
        pgaAggregateTargetGB ||chr(9)||
        physMemoryGB ||chr(9)||
        dNFSenabled ||chr(9)||
        GoldenGate ||chr(9)||
        exadataEnabled ||chr(9)||
        bctEnabled ||chr(9)||
        LogArchiveConfig ||chr(9)||
        ArchiveLagTarget ||chr(9)||
        tablespaceCount ||chr(9)||
        encryptedTablespaceCount ||chr(9)||
        encryptedDataSizeTB ||chr(9)||
        bigfileTablespaceCount ||chr(9)||
        bigfileDataSizeGB ||chr(9)||
        logfileCount ||chr(9)||
        tempfileCount
 from rubrikDataCollection;

spool off

truncate table rubrikDataCollection;

drop table rubrikDataCollection;

exit;
