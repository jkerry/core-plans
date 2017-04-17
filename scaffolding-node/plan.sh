pkg_name=scaffolding-node
pkg_origin=core
pkg_version="0.1.0"
pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
pkg_license=('Apache-2.0')
pkg_source=nope
pkg_build_deps=(chef/inspec)
pkg_upstream_url=https://github.com/habitat-sh/core-plans/tree/master/scaffolding-node

do_download() {
  return 0
}

do_verify() {
  return 0
}

do_unpack() {
  return 0
}

do_build() {
  return 0
}

do_install() {
  install -D -m 0644 "$PLAN_CONTEXT/lib/scaffolding.sh" "$pkg_prefix/lib/scaffolding.sh"
}

do_check() {
  inspec exec "$PLAN_CONTEXT/test"
}
