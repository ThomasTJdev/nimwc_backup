/*
    New blog post
*/

$(document).ready(function() {
  $( "ul.backup a.load" ).click(function() {
    var result = confirm("This will overwrite your current database. Are you sure?");
    if (result) {
      window.location.href = $(this).attr("data-url");
    }
  });
  $( "ul.backup a.delete" ).click(function() {
    var result = confirm("This will delete the backup. Are you sure?");
    if (result) {
      window.location.href = $(this).attr("data-url");
    }
  });

  $( "div.backup.buttons a.backupTime" ).click(function() {
    $("form.backup").toggle();
  });
});