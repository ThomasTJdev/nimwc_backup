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

    let backupDir  = backupDir(db)
    let backupFile = backupDir & @"backupname"
    echo "\n\n\n"
    echo backupFile
    echo "\n\n\n"
    if not fileExists(backupFile):
      redirect("/backup/settings?msg=" & encodeUrl("Error, no backup with that name was found."))

    if @"backupname".contains("tar.gz"):
      let backupDirLoad = backupDir / "load"
      if dirExists(backupDirLoad): removeDir(backupDirLoad)
      createDir(backupDirLoad)

      # Extract archive
      if execCmd("tar -xzf " & backupFile & " -C " & backupDirLoad) != 0:
        redirect("/backup/settings?msg=" & encodeUrl("Error, could not unpack archive."))

      let efspublic   = storageEFS & "/files/public/"
      let efsprivate  = storageEFS & "/files/private/"
      let public      = replace(getAppDir(), "/nimwcpkg", "/public/")
      discard execCmd("cp -R " & backupDirLoad & "/./filespublic/* " & efspublic)
      discard execCmd("cp -R " & backupDirLoad & "/./filesprivate/* " & efsprivate)
      discard execCmd("cp -R " & backupDirLoad & "/./public/* " & public)

      removeDir(backupDirLoad)

    else:
      when defined(postgres):
        redirect("/backup/settings?msg=" & encodeUrl("Error, its not possible to load database on postgres."))
      try:
        copyFile(backupFile, dbDir & "website.db")
      except:
        redirect("/backup/settings?msg=" & encodeUrl("Error, the backup could not be loaded."))

    redirect("/backup/settings?msg=" & encodeUrl("Backup \"" & @"backupname" & "\" was loaded."))


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