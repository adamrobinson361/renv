
local({

  # the requested version of renv
  version <- "0.7.0"

  # signal that we're loading renv during R startup
  Sys.setenv("RENV_R_INITIALIZING" = "true")
  on.exit(Sys.unsetenv("RENV_R_INITIALIZING"), add = TRUE)

  # load the 'utils' package eagerly -- this ensures that renv shims, which
  # mask 'utils' packages, will come first on the search path
  library(utils, lib.loc = .Library)

  # check to see if renv has already been loaded
  if ("renv" %in% loadedNamespaces()) {

    # if renv has already been loaded, and it's the requested version of renv,
    # nothing to do
    spec <- .getNamespaceInfo(.getNamespace("renv"), "spec")
    if (identical(spec[["version"]], version))
      return(invisible(TRUE))

    # otherwise, unload and attempt to load the correct version of renv
    unloadNamespace("renv")

  }

  # attempt to load renv from project library
  root <- Sys.getenv("RENV_PATHS_LIBRARY", unset = "renv/library")
  rversion <- paste("R", getRversion()[1, 1:2], sep = "-")
  libpath <- file.path(root, rversion, R.version$platform)

  # try to load renv from one of these paths
  if (requireNamespace("renv", lib.loc = libpath, quietly = TRUE))
    return(renv::load())

  # failed to find renv locally; we'll try to install from GitHub.
  # first, set up download options as appropriate (try to use GITHUB_PAT)
  install_renv <- function() {

    message("Failed to find installation of renv -- attempting to bootstrap...")

    # ensure .Rprofile doesn't get executed
    rpu <- Sys.getenv("R_PROFILE_USER", unset = NA)
    Sys.setenv(R_PROFILE_USER = "<NA>")
    on.exit({
      if (is.na(rpu))
        Sys.unsetenv("R_PROFILE_USER")
      else
        Sys.setenv(R_PROFILE_USER = rpu)
    }, add = TRUE)

    # prepare download options
    pat <- Sys.getenv("GITHUB_PAT")
    if (nzchar(Sys.which("curl")) && nzchar(pat)) {
      fmt <- "--location --fail --header \"Authorization: token %s\""
      extra <- sprintf(fmt, pat)
      saved <- options("download.file.method", "download.file.extra")
      options(download.file.method = "curl", download.file.extra = extra)
      on.exit(do.call(base::options, saved), add = TRUE)
    } else if (nzchar(Sys.which("wget")) && nzchar(pat)) {
      fmt <- "--header=\"Authorization: token %s\""
      extra <- sprintf(fmt, pat)
      saved <- options("download.file.method", "download.file.extra")
      options(download.file.method = "wget", download.file.extra = extra)
      on.exit(do.call(base::options, saved), add = TRUE)
    }

    # fix up repos
    repos <- getOption("repos")
    on.exit(options(repos = repos), add = TRUE)
    repos[repos == "@CRAN@"] <- "https://cran.rstudio.com"
    options(repos = repos)

    # check for renv on CRAN matching this version
    db <- as.data.frame(available.packages(), stringsAsFactors = FALSE)
    if ("renv" %in% rownames(db)) {
      entry <- db["renv", ]
      if (identical(entry$Version, version)) {
        message("* Installing renv ", version, " ... ", appendLF = FALSE)
        dir.create(libpath, showWarnings = FALSE, recursive = TRUE)
        utils::install.packages("renv", lib = libpath, quiet = TRUE)
        message("Done!")
        return(TRUE)
      }
    }

    # try to download renv
    message("* Downloading renv ", version, " ... ", appendLF = FALSE)
    prefix <- "https://api.github.com"
    url <- file.path(prefix, "repos/rstudio/renv/tarball", version)
    destfile <- tempfile("renv-", fileext = ".tar.gz")
    on.exit(unlink(destfile), add = TRUE)
    utils::download.file(url, destfile = destfile, mode = "wb", quiet = TRUE)
    message("Done!")

    # attempt to install it into bootstrap library
    message("* Installing renv ", version, " ... ", appendLF = FALSE)
    dir.create(libpath, showWarnings = FALSE, recursive = TRUE)
    utils::install.packages(destfile, repos = NULL, type = "source", lib = libpath, quiet = TRUE)
    message("Done!")

  }

  try(install_renv())

  # try again to load
  if (requireNamespace("renv", lib.loc = libpath, quietly = TRUE)) {
    message("Successfully installed and loaded renv ", version, ".")
    return(renv::load())
  }

  # failed to download or load renv; warn the user
  msg <- c(
    "Failed to find an renv installation: the project will not be loaded.",
    "Use `renv::activate()` to re-initialize the project."
  )

  warning(paste(msg, collapse = "\n"), call. = FALSE)

})
