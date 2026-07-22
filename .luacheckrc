globals = { "vim" }
max_line_length = 100

self = false -- unused `self` args are fine

exclude_files = {
  ".deps/",
}

files["tests/"] = {
  globals = { "describe", "it", "before_each", "after_each", "assert", "pending" },
}
