  get "/backup/settings":
    createTFD()
    if not c.loggedIn or c.rank notin [Admin, Moderator]:
      redirect("/")

    resp genMain(c, genBackupSettings(c, db, @"msg"))

  get "/backup/backupsettings":
    createTFD()
    if not c.loggedIn or c.rank notin [Admin, Moderator]:
      redirect("/")

    if (not isDigit(@"backuptime") or "." in @"backuptime") or (not isDigit(@"keepbackup") or "." in @"keepbackup"):
      redirect("/backup/settings?msg=" & encodeUrl("Backup time needs to be a whole number. You provided backuptime: " & @"backuptime" & " and keep backup: " & @"keepbackup"))

    # Update backup time
    let execUno = tryExec(db, sql"UPDATE backup_settings SET value = ?, modified = ? WHERE element = ?", @"backuptime", toInt(epochTime()), "backuptime")

    # Update saving time
    let execDuo = tryExec(db, sql"UPDATE backup_settings SET value = ?, modified = ? WHERE element = ?", @"keepbackup", toInt(epochTime()), "keepbackup")

    # Update backup dir
    var execTres = true
    if @"backupdir" == "" or @"backupdir" == "data/":
      execTres = tryExec(db, sql"UPDATE backup_settings SET value = ?, modified = ? WHERE element = ?", "data/", toInt(epochTime()), "backupdir")
    else:
      execTres = tryExec(db, sql"UPDATE backup_settings SET value = ?, modified = ? WHERE element = ?", @"backupdir", toInt(epochTime()), "backupdir")

    if execUno and execDuo and execTres:
      asyncCheck cronBackup(db)
      redirect("/backup/settings")

    else:
      redirect("/backup/settings?msg=" & encodeUrl("Something went wrong!"))

  get "/backup/loadbackup":
    createTFD()
    if not c.loggedIn or c.rank notin [Admin, Moderator]:
      redirect("/")

    let backupDir = backupDir(db)
    if fileExists(backupDir & @"backupname"):
      echo "cp " & backupDir & @"backupname" & " " & dbDir & "website.db"
      try:
        copyFile(backupDir & @"backupname", dbDir & "website.db")
        redirect("/backup/settings?msg=" & encodeUrl("Backup \"" & @"backupname" & "\" was loaded."))
      except:
        redirect("/backup/settings?msg=" & encodeUrl("Error, the backup could not be loaded."))

    redirect("/backup/settings?msg=" & encodeUrl("Error, no backup with that name was found."))

  get "/backup/backupnow":
    createTFD()
    if not c.loggedIn or c.rank notin [Admin, Moderator]:
      redirect("/")

    if backupNow(db):
      redirect("/backup/settings")
    else:
      redirect("/backup/settings?msg=" & encodeUrl("Error, something went wrong creating the backup."))

  get "/backup/download":
    ## Get a file
    createTFD()
    if not c.loggedIn or c.rank notin [Admin, Moderator]:
      redirect("/")

    let filename = @"backupname"

    var filepath = backupDir(db) & filename

    if not fileExists(filepath):
      redirect("/backup/settings?msg=" & encodeUrl("Error, the backup file was not found with the name: " & filename))

    # Serve the file
    sendFile(filepath)

  get "/backup/delete":
    createTFD()
    if not c.loggedIn or c.rank notin [Admin, Moderator]:
      redirect("/")

    let backupDir = backupDir(db)
    if fileExists(backupDir & @"backupname"):
      let execOutput = execCmd("rm " & backupDir & @"backupname")
      if execOutput == 0:
        redirect("/backup/settings")
      else:
        redirect("/backup/settings?msg=" & encodeUrl("Error, the backup could not be deleted (" & @"backupname" & ")."))