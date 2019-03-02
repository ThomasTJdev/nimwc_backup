const $anyBackups = document.querySelector("ul.backup a.load");
if ($anyBackups != null) {
  document.querySelectorAll("ul.backup a.load").forEach( el => {
    el.addEventListener('click', () => {
      var result = confirm("This will overwrite your current database. Are you sure?");
      if (result) {
        window.location.href = el.getAttribute("data-url");
      }
    });
  });
  document.querySelectorAll("ul.backup a.delete").forEach( el => {
    el.addEventListener('click', () => {
      var result = confirm("This will delete the backup. Are you sure?");
      if (result) {
        window.location.href = el.getAttribute("data-url");
      }
    });
  });
}
const $formBackup = document.querySelector("form.backup");
document.querySelector("div.backup.buttons a.backupTime").addEventListener('click', function () {
  $formBackup.classList.toggle("hidden");
});