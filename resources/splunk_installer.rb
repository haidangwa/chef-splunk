#
# Author: Dang H. Nguyen <dang.nguyen@disney.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
resource_name :splunk_installer

property :url, String
property :package_name, String, name_property: true
property :version, String
property :splunkuser, String, default: splunk_runas_user
property :splunkpassword, String

action_class do
  def package_file
    if new_resource.url.empty? || new_resource.url.nil?
      "#{new_resource.package_name}-#{new_resource.version}"
    else
      splunk_file(new_resource.url)
    end
  end

  def package_version
    new_resource.version || package_file[/#{new_resource.name}-([^-]+)/, 1]
  end

  def cached_package
    "#{Chef::Config[:file_cache_path]}/#{package_file}"
  end

  def local_package_resource
    case node['platform_family']
    when 'rhel', 'fedora', 'suse', 'amazon'
      :rpm_package
    when 'windows'
      :windows_package
    when 'debian'
      :dpkg_package
    end
  end

  def action_installer(installer_action = :install)
    # during an initial install, the start/restart commands must deal with accepting
    # the license. So, we must ensure the service[splunk] resource
    # properly deals with the license; therefore, the `svc_command` method does this
    # for us uniformly regardless of the action
    edit_resource(:service, 'splunk') do
      action installer_action == :upgrade ? :stop : :nothing
      supports status: true, restart: true
      stop_command svc_command('stop')
      start_command svc_command('start')
      restart_command svc_command('restart')
      provider splunk_service_provider
    end

    remote_file package_file do
      backup false
      mode '644'
      path cached_package
      source new_resource.url
      use_conditional_get true
      use_etag true
      action :create
      not_if { new_resource.url.empty? || new_resource.url.nil? }
    end

    declare_resource local_package_resource, new_resource.name do
      action installer_action
      package_name new_resource.package_name

      if new_resource.url.empty? || new_resource.url.nil?
        version package_version
      else
        source cached_package.gsub(/\.Z/, '')
      end

      if platform_family?('windows')
        installer_type :msi
        sensitive true
        options "AGREETOLICENSE=#{license_accepted? ? 'YES' : 'NO'} SPLUNKUSER=#{new_resource.splunkuser} SPLUNKPASSWORD=#{new_resource.splunkpassword} /quiet"
      end

      notifies :stop, 'service[splunk]', :before if installer_action == :upgrade
      
      # forwarders can be restarted immediately; otherwise, wait until the end
      if package_file =~ /splunkforwarder/
        notifies :start, 'service[splunk]', :immediately
      else
        notifies :start, 'service[splunk]'
      end
    end
  end
end

action :run do
  action_installer
end

action :install do
  action_installer
end

action :upgrade do
  return unless splunk_installed?
  if platform_family?('windows')
    # upgrade and install are the same for Windows
    action_installer
  else
    action_installer(:upgrade)
  end
end

action :remove do
  find_resource(:service, 'splunk') do
    supports status: true, restart: true
    provider splunk_service_provider
    action node['init_package'] == 'systemd' ? %i(stop disable) : :stop
  end

  declare_resource local_package_resource, new_resource.name do
    action :remove
    notifies :stop, 'service[splunk]', :before
  end

  user node['splunk']['user']['username'] do
    action :remove
  end

  group node['splunk']['user']['username'] do
    action :remove
  end

  directory splunk_dir do
    recursive true
    action :delete
  end

  file package_file do
    action :delete
    path cached_package
    backup false
  end
end
