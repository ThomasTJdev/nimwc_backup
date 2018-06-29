# Copyright 2018 - Thomas T. Jarløv

import
  asyncdispatch,
  asyncnet,
  db_sqlite,
  os,
  osproc,
  strutils,
  times,
  uri


import ../../nimwcpkg/resources/session/user_data
import ../../nimwcpkg/resources/utils/dates
import ../../nimwcpkg/resources/utils/logging


const pluginTitle       = "Backup"
const pluginAuthor      = "Thomas T. Jarløv"
const pluginVersion     = "0.1"
const pluginVersionDate = "2018-05-20"


proc pluginInfo() =
  echo " "
  echo "--------------------------------------------"
  echo "  Package:      " & pluginTitle & " plugin"
  echo "  Author:       " & pluginAuthor
  echo "  Version:      " & pluginVersion
  echo "  Version date: " & pluginVersionDate
  echo "--------------------------------------------"
  echo " "
pluginInfo()



include "html.tmpl"


var runBackup* = true


proc backupNow*(): bool =
  ## Create backup - copy current database to database_date
  ##
  ## Bool return is used in routes

  let dateName = epochDate($toInt(epochTime()), "YYYY_MM_DD-HH_mm")
  let execOutput = execCmd("cp data/website.db data/website_" & dateName & ".db")
  if execOutput != 0:
    dbg("ERROR", "Backup plugin: Error while backing up data/website_" & dateName & ".db")
    return false
  return true


proc backupDelete*(db: DbConn) =
  ## Delete database older than x

  let backupKeep = getValue(db, sql"SELECT value FROM backup_settings WHERE element = ?", "keepbackup")

  let olderThan = toInt(epochTime()) - parseInt(backupKeep)

  for kind, path in walkDir("data/"):
    if path == "data/website.db":
      continue

    if toUnix(getLastModificationTime(path)) < olderThan:
      if not tryRemoveFile(path):
        dbg("ERROR", "Backup plugin: Error while deleting old backup - " & path)



proc cronBackup*(db: DbConn) {.async.} =
  ## Cron backup run
  ## runBackup needs to be true to run
  
  runBackup = true
  while runBackup:
    let backupmodified = getValue(db, sql"SELECT modified FROM backup_settings WHERE element = ?", "backuptime")
    let backuptime = getValue(db, sql"SELECT value FROM backup_settings WHERE element = ?", "backuptime")

    if backuptime == "" or backuptime == "0":
      runBackup = false
      dbg("DEBUG", "Backup plugin: No backuptime specified. Quitting loop.")

    else:
      when defined(dev):
        dbg("DEBUG", "Backup plugin: Waiting time between cron backup is 15 minute")
        dbg("DEBUG", "Backup plugin: Real waiting time is: " & backuptime & " hours\n")
        await sleepAsync(60 * 15 * 1000) # 15 minutes
        
      when not defined(dev):
        echo "Backup plugin: Waiting " & $(parseInt(backuptime) * 60 * 60) & " seconds before next backup"
        await sleepAsync((parseInt(backuptime) * 60 * 60) * 1000)
      
      # Delete backups older than x
      backupDelete(db)

      # Check if backup is needed
      let backupmodifiedCheck = getValue(db, sql"SELECT modified FROM backup_settings WHERE element = ?", "backuptime")
      if backupmodified != backupmodifiedCheck:
        break

      else:
        discard backupNow()
      


proc backupStart*(db: DbConn) =
  ## Required proc. Will run on each program start
  ##
  ## If there's no need for this proc, just
  ## discard it. The proc may not be removed.

  dbg("INFO", "Backup plugin: Updating database with Backup table if not exists")
  
  if not db.tryExec(sql"""
  create table if not exists backup_settings (
    id INTEGER primary key,
    element TEXT NOT NULL,
    value TEXT NOT NULL,
    modified timestamp not null default (STRFTIME('%s', 'now')),
    creation timestamp not null default (STRFTIME('%s', 'now'))
  );""", []):
    dbg("INFO", "Backup plugin: Backup table created in database")

  if getAllRows(db, sql"SELECT id FROM backup_settings").len() == 0:
    exec(db, sql"INSERT INTO backup_settings (element, value) VALUES (?, ?)", "backuptime", "0")
    exec(db, sql"INSERT INTO backup_settings (element, value) VALUES (?, ?)", "keepbackup", "10")

  asyncCheck cronBackup(db)