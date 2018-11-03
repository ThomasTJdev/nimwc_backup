  get "/backup/settings":
    createTFD()
    if c.loggedIn and c.rank in [Admin, Moderator]:
      resp genMain(c, genBackupSettings(c, db, @"msg"))

  get "/backup/backupsettings":
    createTFD()
    if c.loggedIn and c.rank in [Admin, Moderator]:
      if (not isDigit(@"backuptime") or "." in @"backuptime") or (not isDigit(@"keepbackup") or "." in @"keepbackup"):
        redirect("/backup/settings?msg=" & encodeUrl("Backup time needs to be a whole number. You provided backuptime: " & @"backuptime" & " and keep backup: " & @"keepbackup"))

      let execUno = tryExec(db, sql"UPDATE backup_settings SET value = ?, modified = ? WHERE element = ?", @"backuptime", toInt(epochTime()), "backuptime")

      let execDuo = tryExec(db, sql"UPDATE backup_settings SET value = ?, modified = ? WHERE element = ?", @"keepbackup", toInt(epochTime()), "keepbackup")

      if execUno and execDuo:
        asyncCheck cronBackup(db)
        redirect("/backup/settings")

      else:
        redirect("/backup/settings?msg=" & encodeUrl("Something went wrong!"))

  get "/backup/loadbackup":
    createTFD()
    if c.loggedIn and c.rank in [Admin, Moderator]:
      if fileExists("data/" & @"backupname"):
        let execOutput = execCmd("cp data/" & @"backupname" & " data/website.db")
        if execOutput == 0:
          redirect("/backup/settings?msg=" & encodeUrl("Backup \"" & @"backupname" & "\" was loaded."))
        else:
          redirect("/backup/settings?msg=" & encodeUrl("Error, the backup could not be loaded."))

      redirect("/backup/settings?msg=" & encodeUrl("Error, no backup with that name was found."))

  get "/backup/backupnow":
    createTFD()
    if c.loggedIn and c.rank in [Admin, Moderator]:
      if backupNow():
        redirect("/backup/settings")
      else:
        redirect("/backup/settings?msg=" & encodeUrl("Error, something went wrong creating the backup."))

  get "/backup/download":
    ## Get a file
    createTFD()
    if c.loggedIn and c.rank in [Admin, Moderator]:
      let filename = @"backupname"

      var filepath = "data/" & filename

      if not fileExists(filepath):
        redirect("/backup/settings?msg=" & encodeUrl("Error, the backup file was not found with the name: " & filename))

      # Serve the file
      sendFile(filepath)

  get "/backup/delete":
    createTFD()
    if c.loggedIn and c.rank in [Admin, Moderator]:
      if fileExists("data/" & @"backupname"):
        let execOutput = execCmd("rm data/" & @"backupname")
        if execOutput == 0:
          redirect("/backup/settings")
        else:
          redirect("/backup/settings?msg=" & encodeUrl("Error, the backup could not be deleted (" & @"backupname" & ")."))