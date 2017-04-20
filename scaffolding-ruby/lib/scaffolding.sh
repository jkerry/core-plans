_scaffolding_begin() {
  _setup_funcs
  _setup_vars

  pushd "$SRC_PATH"
  _detect_gemfile
  _detect_missing_gems
  _update_pkg_build_deps
  _update_pkg_deps
  popd

  _update_bin_dirs
  _update_svc_run

  scaffolding_env[PORT]="8000"
  scaffolding_env[RAILS_ENV]="production"
}

do_default_prepare() {
  local gem_dir gem_path

  # Determine Ruby engine, ABI version, and Gem path by running `ruby` itself.
  eval $(ruby -rubygems -rrbconfig - <<-'EOF'
    puts "local ruby_engine=#{defined?(RUBY_ENGINE) ? RUBY_ENGINE : 'ruby'}"
    puts "local ruby_version=#{RbConfig::CONFIG['ruby_version']}"
    puts "local gem_path='#{Gem.path.join(':')}'"
EOF
)

  # Strip out any home directory entries at the front of the gem path.
  gem_path=$(echo "$gem_path" | sed 's|^/root/\.gem/[^:]\{1,\}:||')
  # Compute gem directory where gems will be ultimately installed to
  gem_dir="$scaffolding_app_prefix/vendor/bundle/$ruby_engine/$ruby_version"
  # Compute gem directory where gems are initially installed to via Bundler
  _cache_gem_dir="$CACHE_PATH/vendor/bundle/$ruby_engine/$ruby_version"

  # Silence Bundler warning when run as root user
  export BUNDLE_SILENCE_ROOT_WARNING=1

  export GEM_HOME="$gem_dir"
  build_line "Setting GEM_HOME=$GEM_HOME"
  export GEM_PATH="$gem_dir:$gem_path"
  build_line "Setting GEM_PATH=$GEM_PATH"
}

do_default_build() {
  # TODO fin: add cache loading of `$CACHE_PATH/vendor`

  scaffolding_bundle_install

  # build_line "Cleaning old cached gems"
  # _bundle clean --dry-run --force
  # TODO fin: add cache saving of `$CACHE_PATH/vendor`

  scaffolding_remove_gem_cache
  scaffolding_vendor_bundler
  scaffolding_fix_rubygems_shebangs
  scaffolding_create_process_bins
}

do_default_install() {
  scaffolding_install_app
  scaffolding_create_dir_symlinks
  scaffolding_create_files_symlinks
  scaffolding_install_gems
  scaffolding_generate_binstubs
  scaffolding_install_bundler_binstubs
  scaffolding_fix_binstub_shebangs
  scaffolding_install_process_bins
}

# Lightly modify the stock `do_default_build_service` to inject some
# environment variables.
do_default_build_service() {
  build_line "Writing service management scripts"
  if [[ -f "${PLAN_CONTEXT}/hooks/run" ]]; then
    build_line "Using run hook ${PLAN_CONTEXT}/hooks/run"
    return 0
  else
    if [[ -n "${pkg_svc_run}" ]]; then
      # We use chpst to ensure that the script works outside `hab-sup`
      # for debugging purposes, or under a `hab-director`.
      build_line "Writing ${pkg_prefix}/run script to run ${pkg_svc_run} as ${pkg_svc_user}:${pkg_svc_group}"
      cat <<EOT >> $pkg_prefix/run
#!/bin/sh
export HOME=$pkg_svc_data_path
cd $pkg_svc_path

$(
  for key in "${!scaffolding_env[@]}"; do
    echo "export $key='${scaffolding_env[$key]}'"
  done
)

if [ "\$(whoami)" = "root" ]; then
  exec chpst \\
    -U ${pkg_svc_user}:${pkg_svc_group} \\
    -u ${pkg_svc_user}:${pkg_svc_group} \\
    ${pkg_svc_run} 2>&1
else
  exec ${pkg_svc_run} 2>&1
fi
EOT
    fi
  fi
  return 0
}

# This becomes the `do_default_build_config` implementation thanks to some
# function "renaming" above. I know, right?
_new_do_default_build_config() {
  local key dir

  _stock_do_default_build_config

  if [[ ! -f "$PLAN_CONTEXT/hooks/init" ]]; then
    build_line "No user-defined init hook found, generating init hook"
    mkdir -p "$pkg_prefix/hooks"
    cat <<EOT >> "$pkg_prefix/hooks/init"
#!/bin/sh

$(
  for key in "${!scaffolding_env[@]}"; do
    echo "export $key='${scaffolding_env[$key]}'"
  done
)

# Create a directory for each app symlinked dir under $pkg_svc_var_path
$(
  for dir in "${scaffolding_symlinked_dirs[@]}"; do
    echo "mkdir -pv '$pkg_svc_var_path/$dir'"
  done
)
EOT
    chmod 755 "$pkg_prefix/hooks/init"
  fi
}




scaffolding_bundle_install() {
  local start_sec elapsed

  # Attempt to preserve any original Bundler config by moving it to the side
  if [[ -f .bundle/config ]]; then
    mv .bundle/config .bundle/config.prehab
  fi

  build_line "Installing dependencies using $(_bundle --version)"
  start_sec="$SECONDS"
  _bundle_install \
    "$CACHE_PATH/vendor/bundle" \
    --retry 5
  elapsed=$(($SECONDS-$start_sec))
  elapsed=$(echo $elapsed | awk '{printf "%dm%ds", $1/60, $1%60}')
  build_line "Bundle completed ($elapsed)"

  # If we preserved the original Bundler config, move it back into place
  if [[ -f .bundle/config.prehab ]]; then
    rm -f .bundle/config
    mv .bundle/config.prehab .bundle/config
    rm -f .bundle/config.prehab
  fi
}

scaffolding_remove_gem_cache() {
  build_line "Removing installed gem cache"
  rm -rf "$_cache_gem_dir/cache"
}

scaffolding_vendor_bundler() {
  build_line "Vendoring $(_bundle --version)"
  gem install \
    --local "$(pkg_path_for bundler)/cache/bundler-${_bundler_version}.gem" \
    --install-dir "$_cache_gem_dir" \
    --bindir "$CACHE_PATH/bundler" \
    --no-ri \
    --no-rdoc
  _wrap_ruby_bin "$CACHE_PATH/bundler/bundle"
  _wrap_ruby_bin "$CACHE_PATH/bundler/bundler"
}

scaffolding_fix_rubygems_shebangs() {
  local shebang
  shebang="#!$(pkg_path_for $_ruby_pkg)/bin/ruby"

  find "$_cache_gem_dir/bin" -type f | while read bin; do
    build_line "Fixing Ruby shebang for RubyGems bin '$bin'"
    sed -e "s|^#!.\{0,\}\$|${shebang}|" -i "$bin"
  done
}

scaffolding_create_process_bins() {
  mkdir -pv "$CACHE_PATH/bin"
  _create_process_bin \
    "$CACHE_PATH/bin/${pkg_name}-web" \
    'bundle exec rails server -p $PORT'
}

scaffolding_install_app() {
  build_line "Installing app codebase to $scaffolding_app_prefix"
  mkdir -pv "$scaffolding_app_prefix"
  if [[ -n "${_uses_git:-}" ]]; then
    # Use git commands to skip any git-ignored files and directories including
    # the `.git/ directory. Current on-disk state of all files is used meaning
    # that dirty and unstaged files are included which should help while
    # working on package builds.
    { git ls-files; git ls-files --exclude-standard --others; } \
      | _tar_pipe_app_cp_to "$scaffolding_app_prefix"
  else
    # Use find to enumerate all files and directories for copying. This is the
    # safe-fallback strategy if no version control software is detected.
    find . | _tar_pipe_app_cp_to "$scaffolding_app_prefix"
  fi
}

scaffolding_create_dir_symlinks() {
  local entry dir target

  for entry in "${scaffolding_symlinked_dirs[@]}"; do
    dir="$scaffolding_app_prefix/$entry"
    target="$pkg_svc_var_path/$entry"
    build_line "Creating directory symlink to '$target' for '$dir'"
    rm -rf "$dir"
    mkdir -p "$(dirname "$dir")"
    ln -sfv "$target" "$dir"
  done
}

scaffolding_create_files_symlinks() {
  return 0
}

scaffolding_install_gems() {
  mkdir -pv "$scaffolding_app_prefix/vendor"
  build_line "Installing vendored gems to $scaffolding_app_prefix/vendor/bundle"
  cp -a "$CACHE_PATH/vendor/bundle" "$scaffolding_app_prefix/vendor/"
}

scaffolding_generate_binstubs() {
  build_line "Generating app binstubs in $scaffolding_app_prefix/binstubs"
  rm -rf "$scaffolding_app_prefix/.bundle"
  pushd "$scaffolding_app_prefix" > /dev/null
  _bundle_install \
    "$scaffolding_app_prefix/vendor/bundle" \
    --local \
    --quiet \
    --binstubs="$scaffolding_app_prefix/binstubs"
  popd > /dev/null
}

scaffolding_install_bundler_binstubs() {
  build_line "Installing Bundler binstubs to $scaffolding_app_prefix/binstubs"
  cp -a "$CACHE_PATH/bundler"/* "$scaffolding_app_prefix/binstubs"
}

scaffolding_fix_binstub_shebangs() {
  local shebang
  shebang="#!$(pkg_path_for $_ruby_pkg)/bin/ruby"

  find "$scaffolding_app_prefix/binstubs" -type f | while read binstub; do
    if grep -q '^#!/usr/bin/env /.*/bin/ruby$' "$binstub"; then
      build_line "Fixing Ruby shebang for binstub '$binstub'"
      sed -e "s|^#!/usr/bin/env /.\{0,\}/bin/ruby\$|${shebang}|" -i "$binstub"
    fi
  done
}

scaffolding_install_process_bins() {
  build_line "Installing process bins to $pkg_prefix/bin"
  cp -a "$CACHE_PATH/bin"/* "$pkg_prefix/bin/"
}




_setup_funcs() {
  # Use the stock `do_default_build_config` by renaming it so we can call the
  # stock behavior. How does this rate on the evil scale?
  _rename_function "do_default_build_config" "_stock_do_default_build_config"
  _rename_function "_new_do_default_build_config" "do_default_build_config"
}

_setup_vars() {
  # The default Ruby package if one cannot be detected
  _default_ruby_pkg="core/ruby"
  # The absolute path to the `gemfile-parser` program
  _gemfile_parser="$(pkg_path_for scaffolding-ruby)/bin/gemfile-parser"
  # `$scaffolding_ruby_pkg` is empty by default
  : ${scaffolding_ruby_pkg:=}
  # The list of PostgreSQL-related gems
  _pg_gems=(pg activerecord-jdbcpostgresql-adapter jdbc-postgres
    jdbc-postgresql jruby-pg rjack-jdbc-postgres
    tgbyte-activerecord-jdbcpostgresql-adapter)
  # The version of Bundler in use
  _bundler_version="$(_bundle --version | awk '{print $NF}')"
  # The install prefix path for the app
  scaffolding_app_prefix="$pkg_prefix/app"
  #
  declare -g -A scaffolding_env
  #
  scaffolding_symlinked_dirs=(log tmp public/system)
  scaffolding_symlinked_files=(config/database.yml config/secrets.yml)
}

_detect_gemfile() {
  if [[ ! -f Gemfile ]]; then
    exit_with "Ruby Scaffolding cannot find Gemfile in the root directory" 5
  fi
  if [[ ! -f Gemfile.lock ]]; then
    build_line "No Gemfile.lock found, running 'bundle lock'"
    _bundle lock
  fi
}

_detect_missing_gems() {
  if ! _has_gem tzinfo-data; then
    local e
    e="A required gem 'tzinfo-data' is missing from the Gemfile."
    e="$e If a 'gem \"tzinfo-data\", platforms: [...]' line exists,"
    e="$e simply remove the comma and 'platforms:' section,"
    e="$e rerun 'bundle install' to update the Gemfile.lock, and retry the build."
    exit_with "$e" 10
  fi
}

_update_pkg_build_deps() {
  # Order here is important--entries which should be first in
  # `${pkg_build_deps[@]}` should be called last.

  _detect_git
}

_update_pkg_deps() {
  # Order here is important--entries which should be first in `${pkg_deps[@]}`
  # should be called last.

  _add_busybox
  _detect_sqlite3
  _detect_postgresql
  _detect_nokogiri
  _detect_execjs
  _detect_webpacker
  _detect_ruby
}

_update_bin_dirs() {
  # Add the `bin/` directory and the app's `binstubs/` directory to the bin
  # dirs so they will be on `PATH.  We do this after the existing values so
  # that the Plan author's `${pkg_bin_dir[@]}` will always win.
  pkg_bin_dirs=(
    ${pkg_bin_dir[@]}
    bin
    $(basename $scaffolding_app_prefix)/binstubs
  )
}

_update_svc_run() {
  if [[ -z "$pkg_svc_run" ]]; then
    pkg_svc_run="$pkg_prefix/bin/${pkg_name}-web"
    build_line "Setting pkg_svc_run='$pkg_svc_run'"
  fi
}




_add_busybox() {
  build_line "Adding Busybox package to run dependencies"
  pkg_deps=(core/busybox-static ${pkg_deps[@]})
  debug "Updating pkg_deps=(${pkg_deps[*]}) from Scaffolding detection"
}

_detect_execjs() {
  if _has_gem execjs; then
    build_line "Detected 'execjs' gem in Gemfile.lock, adding node packages"
    pkg_deps=(core/node ${pkg_deps[@]})
    debug "Updating pkg_deps=(${pkg_deps[*]}) from Scaffolding detection"
  fi
}

_detect_git() {
  if [[ -d ".git" ]]; then
    build_line "Detected '.git' directory, adding git packages as build deps"
    pkg_build_deps=(core/git ${pkg_build_deps[@]})
    debug "Updating pkg_build_deps=(${pkg_build_deps[*]}) from Scaffolding detection"
    _uses_git=true
  fi
}

_detect_nokogiri() {
  if _has_gem nokogiri; then
    build_line "Detected 'nokogiri' gem in Gemfile.lock, adding libxml2 & libxslt packages"
    export BUNDLE_BUILD__NOKOGIRI="--use-system-libraries"
    pkg_deps=(core/libxml2 core/libxslt ${pkg_deps[@]})
    debug "Updating pkg_deps=(${pkg_deps[*]}) from Scaffolding detection"
  fi
}

_detect_postgresql() {
  for gem in "${_pg_gems[@]}"; do
    if _has_gem "$gem"; then
      build_line "Detected '$gem' gem in Gemfile.lock, adding postgresql package"
      pkg_deps=(core/postgresql ${pkg_deps[@]})
      debug "Updating pkg_deps=(${pkg_deps[*]}) from Scaffolding detection"
      _uses_postgresql=true
      return 0
    fi
  done
}

_detect_ruby() {
  local lockfile_version

  if [[ -n "$scaffolding_ruby_pkg" ]]; then
    _ruby_pkg="$scaffolding_ruby_pkg"
    build_line "Detected Ruby version in Plan, using '$_ruby_pkg'"
  else
    lockfile_version="$($_gemfile_parser ruby-version ./Gemfile.lock || true)"
    if [[ -n "$lockfile_version" ]]; then
      # TODO fin: Add more robust Gemfile to Habitat package matching
      case "$lockfile_version" in
        *)
          _ruby_pkg="core/ruby/$(
            echo "$lockfile_version" | cut -d ' ' -f 2)"
          ;;
      esac
      build_line "Detected Ruby version '$lockfile_version' in Gemfile.lock, using '$_ruby_pkg'"
    else
      _ruby_pkg="$_default_ruby_pkg"
      build_line "No Ruby version detected in Plan or Gemfile.lock, using default '$_ruby_pkg'"
    fi
  fi
  pkg_deps=($_ruby_pkg ${pkg_deps[@]})
  debug "Updating pkg_deps=(${pkg_deps[*]}) from Scaffolding detection"
}

_detect_sqlite3() {
  if _has_gem sqlite3; then
    build_line "Detected 'sqlite3' gem in Gemfile.lock, adding sqlite packages"
    pkg_deps=(core/sqlite ${pkg_deps[@]})
    debug "Updating pkg_deps=(${pkg_deps[*]}) from Scaffolding detection"
  fi
}

_detect_webpacker() {
  if _has_gem webpacker; then
    build_line "Detected 'webpacker' gem in Gemfile.lock, adding yarn packages"
    pkg_deps=(core/yarn ${pkg_deps[@]})
    debug "Updating pkg_deps=(${pkg_deps[*]}) from Scaffolding detection"
  fi
}




_bundle() {
  "$(pkg_path_for bundler)/bin/bundle" ${*:-}
}

_bundle_install() {
  local path binstubs
  path="$1"
  shift

  _bundle install ${*:-} \
    --jobs "$(nproc)" \
    --without development:test \
    --path "$path" \
    --shebang="$(pkg_path_for "$_ruby_pkg")/bin/ruby" \
    --no-clean \
    --deployment
}

_create_process_bin() {
  local bin cmd
  bin="$1"
  cmd="$2"

  build_line "Creating ${bin} process bin"
  cat <<EOF > "$bin"
#!$(pkg_path_for busybox-static)/bin/sh
set -e
if test -n "\$DEBUG"; then set -x; fi
cd $scaffolding_app_prefix

exec $cmd
EOF
  chmod -v 755 "$bin"
}

_has_gem() {
  local result
  result="$($_gemfile_parser has-gem ./Gemfile.lock "$1" 2> /dev/null || true)"

  if [[ "$result" == "true" ]]; then
    return 0
  else
    return 1
  fi
}

# Heavily inspired from:
# https://gist.github.com/Integralist/1e2616dc0b165f0edead9bf819d23c1e
_rename_function() {
  local orig_name new_name
  orig_name="$1"
  new_name="$2"

  declare -F "$orig_name" > /dev/null \
    || exit_with "No function named $orig_name, aborting" 97
  eval "$(echo "${new_name}()"; declare -f $orig_name | tail -n +2)"
}

# **Internal** Use a "tar pipe" to copy the app source into a destination
# directory. This function reads from `stdin` for its file/directory manifest
# where each entry is on its own line ending in a newline. Several filters and
# changes are made via this copy strategy:
#
# * All user and group ids are mapped to root/0
# * No extended attributes are copied
# * Some file editor backup files are skipped
# * Some version control-related directories are skipped
# * Any `./habitat/` directory is skipped
_tar_pipe_app_cp_to() {
  local dst_path tar
  dst_path="$1"
  tar="$(pkg_path_for tar)/bin/tar"

  "$tar" -cp \
      --owner=root:0 \
      --group=root:0 \
      --no-xattrs \
      --exclude-backups \
      --exclude-vcs \
      --exclude='habitat' \
      --files-from=- \
      -f - \
  | "$tar" -x \
      -C "$dst_path" \
      -f -
}

_wrap_ruby_bin() {
  local bin="$1"
  build_line "Adding wrapper $bin to ${bin}.real"
  mv -v "$bin" "${bin}.real"
  cat <<EOF > "$bin"
#!$(pkg_path_for busybox-static)/bin/sh
set -e
if test -n "\$DEBUG"; then set -x; fi

export GEM_HOME="$GEM_HOME"
export GEM_PATH="$GEM_PATH"
unset RUBYOPT GEMRC

exec $(pkg_path_for $_ruby_pkg)/bin/ruby ${bin}.real \$@
EOF
  chmod -v 755 "$bin"
}
