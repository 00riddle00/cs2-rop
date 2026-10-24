if (file.exists("renv/activate.R")) {
  source("renv/activate.R")
}

# A good practice is not to rely on .Rhistory files.
# <<Uncomment when ready to disable history>>
#options(save.history = FALSE)  # no .Rhistory

# Load local history file at startup (if it exists).
# <<If history needs to be disabled, remove/comment this out>>
if (interactive()) {
  local({
    path <- "./.Rhistory"  # project-local history file
    if (file.exists(path)) {
      try(loadhistory(path), silent = TRUE)
    }
  })
}

# Save history on exit (independent of workspace saving)
# <<If history needs to be disabled, remove/comment this out>>
.Last <- function() {
  if (!interactive()) return()
  try(savehistory("./.Rhistory"), silent = TRUE)
}
