# Copyright 2018 - Thomas T. Jarløv

import
  algorithm,
  asyncdispatch,
  asyncnet,
  datetime2human,
  logging,
  os,
  osproc,
  parsecfg,
  strutils,
  times,
  uri

when defined(postgres): import db_postgres
else:                   import db_sqlite

import ../../nimwcpkg/resources/administration/createdb
import ../../nimwcpkg/resources/files/files_efs
import ../../nimwcpkg/resources/session/user_data
import ../../nimwcpkg/resources/utils/logging_nimwc
import ../../nimwcpkg/resources/utils/plugins

proc pluginInfo() =
  let (n, v, d, u) = pluginExtractDetails("backup")
  echo " "
  echo "--------------------------------------------"
  echo "  Package:      " & n
  echo "  Version:      " & v
  echo "  Description:  " & d
  echo "  URL:          " & u
  echo "--------------------------------------------"
  echo " "
pluginInfo()



include "html.tmpl"

let dict    = loadConfig(replace(getAppDir(), "/nimwcpkg", "") & "/config/config.cfg")
let dbName  = dict.getSectionValue("Database", when defined(postgres): "name" else: "host")

let dbDir*  = parentDir(getAppDir()) & "/data/"

var runBackup* = true


proc backupDir*(db: DbConn): string =
  ## Get path to backups

  let dir = getValue(db, sql"SELECT value FROM backup_settings WHERE element = ?", "backupdir")

  if dir == "" or dir == "backup/":
    return parentDir(getAppDir()) & "/backup/"
  else:
    if not existsOrCreateDir(dir):
      info("Backup plugin: Creating backup dir " & dir)
    return dir


proc backupNow*(db: DbConn): bool =
  ## Create backup - copy current database to database_date
  ##
  ## Bool return is used in routes

  let backupDir     = backupDir(db)
  let backupDirTmp  = backupDir / "tmpfiles"
  let dateName      = epochDate($toInt(epochTime()), "YYYY_MM_DD-HH_mm")

  # Files
  let efspublic   = storageEFS & "/files/public/"
  let efsprivate  = storageEFS & "/files/private/"
  let public      = replace(getAppDir(), "/nimwcpkg", "/public")

  if findExe("tar").len() > 0:
    if dirExists(backupDirTmp): removeDir(backupDirTmp)
    createDir(backupDirTmp)
    createDir(backupDirTmp / "filespublic")
    createDir(backupDirTmp / "filesprivate")
    createDir(backupDirTmp / "public")
    discard execCmd("cp -R " & efspublic & "* " & backupDirTmp & "/filespublic/")
    discard execCmd("cp -R " & efsprivate & "* " & backupDirTmp & "/filesprivate/")
    discard execCmd("cp -R " & public & "* " & backupDirTmp & "/public/")
    # Create archive
    discard execCmd("tar -czf " & backupDir & "/website_" & dateName & "_files.tar.gz -C " & backupDirTmp & " .")

    removeDir(backupDirTmp)


  # Database
  let (backOut, backExitcode) = backupDb(dbName, filename=backupDir / "website_" & dateName & ".db", checksum=false, sign=false, targz=false)

  if backExitcode != 0:
    error("Backup plugin: Error while backing up " & backupDir & "website_" & dateName & ".db")
    return false
  return true


proc backupDelete*(db: DbConn) =
  ## Delete database older than x

  let backupKeep = getValue(db, sql"SELECT value FROM backup_settings WHERE element = ?", "keepbackup")
  if backupKeep == "" or backupKeep == "0":
    return

  let olderThan = toInt(epochTime()) - parseInt(backupKeep)
  let backupDir = backupDir(db)

  for kind, path in walkDir(backupDir):
    if path == backupDir & "website.db":
      continue

    if toUnix(getLastModificationTime(path)) < olderThan:
      if not tryRemoveFile(path):
        error("Backup plugin: Error while deleting old backup - " & path)



proc cronBackup*(db: DbConn) {.async.} =
  ## Cron backup run
  ## runBackup needs to be true to run

  runBackup = true
  while runBackup:
    let backupmodified = getValue(db, sql"SELECT modified FROM backup_settings WHERE element = ?", "backuptime")
    let backuptime = getValue(db, sql"SELECT value FROM backup_settings WHERE element = ?", "backuptime")

    if backuptime == "" or backuptime == "0":
      runBackup = false
      debug("Backup plugin: No backuptime specified. Quitting loop.")
      break

    else:
      when defined(dev):
        debug("Backup plugin: Waiting time between cron backup is 15 minute")
        debug("Backup plugin: Real waiting time is: " & backuptime & " hours\n")
        await sleepAsync(60 * 15 * 1000) # 15 minutes

      when not defined(dev):
        echo "Backup plugin: Waiting " & $(parseInt(backuptime) * 60 * 60) & " seconds before next backup"
        await sleepAsync((parseInt(backuptime) * 60 * 60) * 1000)

      # Delete backups older than x
      backupDelete(db)

      # Check if backup is needed
      let backupmodifiedCheck = getValue(db, sql"SELECT modified FROM backup_settings WHERE element = ?", "backuptime")
      if backupmodified != backupmodifiedCheck:
        continue

      else:
        discard backupNow(db)



proc backupStart*(db: DbConn) =
  ## Required proc. Will run on each program start
  ##
  ## If there's no need for this proc, just
  ## discard it. The proc may not be removed.

  info("Backup plugin: Updating database with Backup table if not exists")

  if not db.tryExec(sql"""
  create table if not exists backup_settings (
    id INTEGER primary key,
    element TEXT NOT NULL,
    value TEXT NOT NULL,
    modified timestamp not null default (STRFTIME('%s', 'now')),
    creation timestamp not null default (STRFTIME('%s', 'now'))
  );""", []):
    info("Backup plugin: Backup table created in database")

  if getValue(db, sql"SELECT id FROM backup_settings WHERE element = ?", "backuptime").len() == 0:
    exec(db, sql"INSERT INTO backup_settings (element, value) VALUES (?, ?)", "backuptime", "0")
  if getValue(db, sql"SELECT id FROM backup_settings WHERE element = ?", "keepbackup").len() == 0:
    exec(db, sql"INSERT INTO backup_settings (element, value) VALUES (?, ?)", "keepbackup", "0")
  if getValue(db, sql"SELECT id FROM backup_settings WHERE element = ?", "backupdir").len() == 0:
    exec(db, sql"INSERT INTO backup_settings (element, value) VALUES (?, ?)", "backupdir", "backup/")

  asyncCheck cronBackup(db)