#
# Cookbook Name:: osrm
# Recipe:: default
#
# Copyright 2016, Swiss OpenStreetMap Assosication
#           2017  Michael Spreng
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "apache"
include_recipe "apache::ssl"

basedir = node[:accounts][:system][:osrm][:home]
osmdata = "#{basedir}/osmdata/osmdata.pbf"
profiles = ["car", "bike", "foot"]
routed_port = 3331
frontenddomain = ""
website_dir = "/var/www/routing"

# Building OSRM (only on installation)
package "git"
package "build-essential"
package "cmake" 
package "pkg-config"
package "libprotoc-dev"
package "protobuf-compiler"
package "libprotobuf-dev"
package "libosmpbf-dev"
package "libpng12-dev"
package "libbz2-dev"
package "libstxxl-dev"
package "libstxxl-doc"
package "libstxxl1v5"
package "libxml2-dev"
package "libzip-dev"
package "libboost-thread-dev"
package "libboost-system-dev"
package "libboost-regex-dev"
package "libboost-filesystem-dev"
package "libboost-program-options-dev"
package "libboost-iostreams-dev"
package "libboost-test-dev"
package "liblua5.2-dev"
package "libluabind-dev"
package "libtbb-dev"
package "libexpat-dev"
package "node-browserify-lite"
package "nodejs-legacy"
package "npm"
package "libboost-python-dev"
package "python3-dev"
package "python3-setuptools"

# munin
package "munin-node"
package "munin"
package "smartmontools"
package "libwww-perl"
package "libcgi-fast-perl"
package "libapache2-mod-fcgid"

# about page
package "python-markdown"

directory "#{basedir}" do
    user  "osrm"
    group "osrm"
end

directory "#{basedir}/data" do
  owner "osrm"
  group "osrm"
end

directory "#{basedir}/extract" do
  owner "root"
  group "root"
end

directory "#{basedir}/scripts" do
  owner "root"
  group "root"
end

execute "compile_osrm" do
  action :nothing
  cwd "#{basedir}/osrm-backend"
  # use -DCMAKE_BUILD_TYPE=RelWithDebInfo for debugging 
  command "rm -rf build && mkdir -p build && cd build "\
          "&& cmake -DCMAKE_BUILD_TYPE=Release .. && make -j 6"
  user "osrm"
end

git "#{basedir}/osrm-backend" do
  repository "git://github.com/fossgis-routing-server/osrm-backend.git"
  revision "e4e5f0ac299c3a302b168344c1d932c7e0e56000"
  user "osrm"
  group "osrm"
  notifies :run, "execute[compile_osrm]", :immediately
end

template "#{basedir}/osrm-backend/build/.stxxl" do
  source "stxxl.erb"
  user   "osrm"
  group  "osrm"
  mode 0644
  variables :basedir => basedir
end

directory website_dir do
    user  "osrm"
    group "osrm"
end

if !node[:osrm][:preprocess]

  frontenddomain=node[:osrm][:frontenddomain]

  execute "compile_osrm_frontend" do
    action :nothing
    cwd "#{basedir}/osrm-frontend"
    environment 'HOME' => "#{basedir}/osrm-frontend"
    command "npm install && npm run build && "\
        "cp -r css fonts images bundle.js bundle.js.map "\
        "bundle.raw.js index.html #{website_dir}"
    user "osrm"
  end

  git "#{basedir}/osrm-frontend" do
    repository "git://github.com/fossgis-routing-server/osrm-frontend.git"
    revision "9e2c9f3ba7508c4eefaaad932de341dfb98d65a4"
    user "osrm"
    group "osrm"
    notifies :run, "execute[compile_osrm_frontend]", :immediately
  end

  directory "#{basedir}/about/" do
      user  "osrm"
      group "osrm"
  end

  # about page

  git "#{basedir}/about/splendor/" do
    repository "https://github.com/markdowncss/splendor.git"
    revision "40db29539e4e8c733dec7f941833dcc21ed60504"
    user "osrm"
    notifies :run, "execute[create_about_page]"
  end


  cookbook_file "#{basedir}/about/about.md" do
    source "about.md"
    user "osrm"
    notifies :run, "execute[create_about_page]"
  end

  execute "create_about_page" do
    action :nothing
    cwd "#{basedir}/about"
    command "cp splendor/css/splendor.css #{website_dir}/splendor.css && "\
        "echo '<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">"\
        "<title>About #{frontenddomain}</title>"\
        "<link rel=\"stylesheet\" href=\"splendor.css\">"\
        "</head><body>' > #{website_dir}/about.html && "\
        "markdown_py about.md -o html5 >> #{website_dir}/about.html && "\
        "echo '</body></html>' >> #{website_dir}/about.html"
    user "osrm"
  end
end

git "#{basedir}/cbf-routing-profiles" do
  repository "git://github.com/fossgis-routing-server/cbf-routing-profiles.git"
  revision "25ff4d6ffa030765a6d86c508011924847a0869e"
  user "osrm"
  group "osrm"
end

# planet
if node[:osrm][:preprocess]
  directory "#{basedir}/osmdata" do
      user  "osrm"
      group "osrm"
  end

  execute "get_data" do
    cwd "#{basedir}/osmdata"
    user "osrm"
    not_if { File.exists?(osmdata) }
    command "wget http://planet.osm.org/pbf/planet-latest.osm.pbf -nc -O #{osmdata}"
  end

  execute "compile_pyosmium" do
    action :nothing
    cwd "#{basedir}/pyosmium"
    command "python3 steup.py build"
    user "osrm"
  end

  git "#{basedir}/pyosmium" do
    repository "https://github.com/osmcode/pyosmium.git"
    revision "v2.13.0"
    user "osrm"
    group "osrm"
    notifies :run, "execute[compile_pyosmium]", :immediately
  end

  git "#{basedir}/libosmium" do
    repository "https://github.com/osmcode/libosmium.git"
    revision "v2.13.1"
    user "osrm"
    group "osrm"
  end

  execute "compile_osmium-tool" do
    action :nothing
    cwd "#{basedir}/osmium-tool"
    command "rm -f build; mkdir build && cd build && cmake .. && make -j 8"
    user "osrm"
  end

  git "#{basedir}/osmium-tool" do
    repository "https://github.com/osmcode/osmium-tool.git"
    revision "v1.7.1"
    user "osrm"
    group "osrm"
    notifies :run, "execute[compile_osmium-tool]", :immediately
  end

  template "#{basedir}/scripts/build-graphs.sh" do
    source "build-graphs.erb"
    mode 0755
    variables :basedir => basedir, :osmdata => osmdata, :profiles => profiles.join(" ")
  end

  template "/etc/systemd/system/build-graphs.service" do
    source "systemd-build-graphs.erb"
    variables :basedir => basedir
  end
else

  template "#{basedir}/scripts/new-graphs.sh" do
    source "new-graphs.erb"
    mode 0755
    variables :basedir => basedir, :profiles => profiles.join(" ")
  end

  template "/etc/cron.d/new-graphs" do
      source "cron-new-graphs.erb"
      user   "root"
      group  "root"
      mode   "0644"
      variables :basedir => basedir
  end

end

cookbook_file "#{basedir}/extract/bike.geojson" do
  source "eurasien.geojson"
  user "root"
end


current_port = routed_port
for profile in profiles do
  template "#{basedir}/cbf-routing-profiles/profile-#{profile}.conf" do
    source "profiles.erb"
    user   "osrm"
    group  "osrm"
    variables :basedir => basedir, :osmdata => "#{basedir}/osmdata/#{profile}.pbf", \
        :profile => profile, :port => current_port
  end

  template "/etc/systemd/system/osrm-routed-#{profile}.service" do
    source "systemd-osrm-routed.erb"
    variables :basedir => basedir, :profile => profile, :port => current_port
  end

  current_port = current_port + 1
end

directory "/var/log/osrm" do
  owner "osrm"
  group "osrm"
  mode 0755
end

directory "#{basedir}/build" do
  owner "osrm"
  if node[:osrm][:preprocess]
    group "osrm"
  else
    group "osrmdata"
  end
  mode 0775
end

# munin

service 'munin-node' do
action [:enable, :start]
end

node['munin']['plugin']['list'].each do |name, thing|
    link "/etc/munin/plugins/#{name}#{thing}" do
        to "/usr/share/munin/plugins/#{name}"
        owner 'root'
        group 'root'
        notifies :restart, 'service[munin-node]'
    end
end

# Apache configuration

apache_module "proxy"
apache_module "proxy_http"
apache_module "rewrite"

apache_site "routing.openstreetmap.de" do
    template "apache.erb"
    directory website_dir
    variables :domain => "#{node[:myhostname]}.#{node[:rooturl]}",\
            :munindir => "/var/cache/munin/www", :port => 80,\
            :preprocessor => node[:osrm][:preprocess],\
            :maindomain => frontenddomain
end

apache_site "routing.openstreetmap.de-ssl" do
    template "apache.erb"
    directory website_dir
    variables :domain => "#{node[:myhostname]}.#{node[:rooturl]}",\
            :munindir => "/var/cache/munin/www", :port => 443,\
            :preprocessor => node[:osrm][:preprocess],\
            :maindomain => frontenddomain
end


