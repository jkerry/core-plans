# encoding: utf-8
#
# Copyright: Copyright (c) 2017 Chef Software, Inc.
# License: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# These controls build the example plans in examples and ensure they install a
# package and run the command specified.
%w{ pkg_source_git_https
    pkg_source_npm_registry
    pkg_source_tarball }.each do |example|
  control "Habitat Node.js Scaffolding (#{example} example)" do
    describe command("hab pkg exec #{ENV['HAB_ORIGIN']}/docco docco --version") do
      let(:build) { "build" }
      # This could be overriden to use another build of the build script:
      let(:build) { "hab pkg exec smith/hab-plan-build hab-plan-build" }

      before do
        command("#{build} /src/scaffolding-node/examples/#{example}")
      end

      its(:stdout) { should eq "0.7.0\n" }
      its(:exit_status) { should eq 0 }
    end
  end
end

control "TODO" do
  describe command(true) do
    it "parses the name from package.json into pkg_name"
    it "parses the version from package.json into pkg_version"
    it "parses the description from pkg_description into pkg_description"
    it "parses the homepage from pkg_description into pkg_upstream_url"
    it "parses the maintainers from npm user info into pkg_maintainer"
    it "parses the license from package.json into pkg_license"
    it "parses the bin from package.json into pkg_bin_dirs"
    it "parses the directories.lib from package.json into pkg_lib_dirs"
    it "works with node packages with git ssh urls as dependencies"
    it "works with node packages with git https urls as dependencies"
    it "parses the engines from package.json into pkg_deps=(core/node/$VERSION)"
    it "lets a service run with `node server.js` if that file exists"
    it "parses the scripts.start from package.json into pkg_svc_run"
    it "sets the npm config group to the value of pkg_svc_group"
    it "sets the npm config user to the value of pkg_svc_user"
    it "works with plans that have no pkg_source and use the app in the parent directory"
    it "works with plans that have pkg_source as a path"
    it "works with plans with multiple pkg_bin_dirs"
  end
end
