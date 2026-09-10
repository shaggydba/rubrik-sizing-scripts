##########
#
# Rubrik Data Collection for Oracle Tooling
#
# Version: 2.1
#
# Developer: Shawn McElhinney
#
# Purpose:
# This utility is designed to collect data from Oracle databases to assist with Rubrik solution sizing.
# The utility will connect to the databases you define in collectionInput.lst and execute the appropriate rbkDataCollection.sql (based on your db version) to gather the data required 
# to begin properly sizing your Rubrik solution for Oracle.
#
# Component files:
# collectionInput.lst -- a space-separated list of the databases in your landscape. Simply provide single line entries for each database in the following format:
# hostname databasePort OracleSID databaseRelease
# where databaseRelease is in a 3 digit format representing MAJOR and DOT release. For example: 10gR2 -> 102; 11gR2 -> 112; 12cR1 -> 121 etc.
# save this file after update as it will be an input for the shell script.
#
# rbkDataCollection.sql -- sql script that collects pertinent database information to assist with sizing Rubrik for Oracle and dump output to a tab-delimited file named rbkDiscovery.csv. Fields are tab-delimited (not comma) since several collected values, such as LOGARCHIVECONFIG and PATCHLEVEL, can legitimately contain commas.
#
# dataCollector.sh -- This script will verify the existence of SQL*Plus, read through collectioInput.lst, execute rbkDataCollection.sql, and write the rbkDiscovery.csv header once at the start of a fresh collection run. At runtime, user will be prompted to enter the SYSTEM password for the associated databases. Output from the sql queries are appended to rbkDiscovery.csv, which is what your Rubrik Sales Engineer will require to help with sizing.
#
# Execution Steps:
# 1 - Update collectionInput.lst file with all Oracle databases that will be integrated with Rubrik. Enter the hostname, databasePort, ORACLE_SID and version for each instance or CDB (please check the expected format in collectionInput.lst-EXAMPLE file). If you utilizes PDB's in 12c+, the script will gather information for all PDBs that are installed in the CDB, plus one extra rollup row (CON_ID=0, CONNAME = the CDB name) summarizing the whole CDB as a single database -- CON_ID=0 identifies exactly one row per database, whether it's a CDB or a standalone (11g-style) instance. If you utilizes RAC cluster, please add the instances of one node only.
#
# 2 - Ensure you have the SYSTEM password for all databases referenced in collectionInput.lst file. 
#
# 3 - Execute dataCollector.sh from an interactive terminal session (not cron, or ssh without a pty) and provide the SYSTEM password when prompted for each database listed in collectionInput.lst. The password is read directly from the terminal and is never passed on a command line or logged.
#
# 4 - Compress the resulting rbkDiscovery.csv & work with your Rubrik Sales Engineer to transfer the file to them via the most secure mechanism available.
#
##########
#
# Version 2.1 Updates (2026-09-09):
#
# - rbkDataCollection.sql, _121.sql, and _12c.sql now add one rollup row per CDB, with
#   CON_ID=0 and CONNAME set to just the CDB name (the root's own name without the
#   ".CDB$ROOT" suffix). Storage fields (DBSIZETB, ALLOCATED_DBSIZETB, ENCRYPTEDDATASIZETB,
#   DATAFILECOUNT, TABLESPACECOUNT, ENCRYPTEDTABLESPACECOUNT, BIGFILETABLESPACECOUNT,
#   BIGFILEDATASIZEGB, LOGFILECOUNT, TEMPFILECOUNT) are summed across that CDB's real PDBs
#   only (excluding CDB$ROOT and PDB$SEED, which stay as their own separate rows).
#   DAILYREDOSIZETB is copied from the root row rather than summed, since the root already
#   holds the CDB-wide redo total and summing the PDBs into it too would double-count it.
#   BIGGESTBIGFILEGB, GOLDENGATE, and EXADATAENABLED use MAX() across the root and its PDBs,
#   since those can each vary by container. Every other column is copied from the root row.
# - This makes CON_ID=0 consistently mean "one row per database" across every script
#   version: it already did for standalone (11g-style) databases, and now it does for CDBs
#   too, without removing the existing per-PDB detail rows.
#
##########
#
# Version 2.0 Updates (2026-09-03):
#
# - Changed the rbkDiscovery.csv field delimiter from comma to a tab character (chr(9)), since
#   some collected values (e.g. LOGARCHIVECONFIG, PATCHLEVEL) can legitimately contain commas.
#   Added SET DEFINE OFF to the SQL scripts so an "&" in a collected value is not treated as a
#   SQL*Plus substitution-variable prompt.
# - dataCollector.sh now writes the rbkDiscovery.csv header once at the start of a fresh
#   collection run, instead of the header never being generated at all.
# - DBSIZEMB, ALLOCATED_DBSIZEMB, ENCRYPTEDDATASIZEMB, and DAILYREDOSIZE are now reported in TB
#   (6 decimal places) as DBSIZETB, ALLOCATED_DBSIZETB, ENCRYPTEDDATASIZETB, and
#   DAILYREDOSIZETB. This also fixes an inconsistency where DAILYREDOSIZE was previously
#   returned in raw bytes by some script versions and in MB by others.
# - BIGGESTBIGFILEMB and BIGFILEDATASIZEMB are now reported in GB (6 decimal places) as
#   BIGGESTBIGFILEGB and BIGFILEDATASIZEGB.
# - SGAMAXSIZE, SGATARGET, PGAAGGREGATETARGET, and PHYSMEMORY are now reported in GB at full
#   precision (not rounded) as SGAMAXSIZEGB, SGATARGETGB, PGAAGGREGATETARGETGB, and
#   PHYSMEMORYGB, instead of raw bytes.
# - Fixed DBSIZETB and ALLOCATED_DBSIZETB returning blank instead of 0 for containers with no
#   visible segments or datafiles, such as PDB$SEED.
# - dataCollector.sh no longer builds the sqlplus connection string with eval, which embedded
#   the SYSTEM password directly on the command line and re-parsed it through the shell. The
#   password is now fed to sqlplus via a CONNECT statement over stdin, closing a command
#   injection risk and keeping the password out of `ps` output. A failed connection now reports
#   which database failed instead of failing silently.
#
##########
