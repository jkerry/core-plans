_scaffolding_begin() {
  pkg_build_deps=(${pkg_deps[@]} core/grep)
  pkg_deps=(${pkg_deps[@]} core/coreutils core/node)
}

do_default_download() {
  return 0
}

do_default_unpack() {
  return 0
}

do_default_verify() {
  return 0
}

scaffolding_node_prepare() {
  export npm_config_prefix="$pkg_prefix"
  build_line "Setting npm_config_prefix=$npm_config_prefix"
  export npm_config_global=true
  build_line "Setting npm_config_global=$npm_config_global"
  if [[ -n "$HAB_NONINTERACTIVE" ]]; then
    export npm_config_progress=false
    build_line "Setting npm_config_progress=$npm_config_progress"
  fi
}

do_default_prepare() {
  scaffolding_node_prepare
}

do_default_build() {
  return 0
}

scaffolding_node_install() {
  npm install "$pkg_source"

  grep -l -R ^\#\!/usr/bin/env "$pkg_prefix" | while IFS= read -r f; do
    fix_interpreter "$(readlink -f "$f")" core/coreutils bin/env
  done
}

do_default_install() {
  scaffolding_node_install
}
