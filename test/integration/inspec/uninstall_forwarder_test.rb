# Inspec tests for splunk forwarder on linux systems.
SPLUNK_HOME = '/opt/splunkforwarder'.freeze
SPLUNK_ENCRYPTED_STRING_REGEX = /\$\d\$.*==$/.freeze

control 'Splunk Universal Forwarder' do
  title 'Verify Splunk Universal Forwarder installation'
  only_if { os.linux? }

  describe package('splunkforwarder') do
    it { should_not be_installed }
  end

  describe.one do
    describe service('SplunkForwarder') do
      it { should_not be_running }
      it { should_not be_enabled }
      it { should_not be_installed }
    end
    describe service('splunk') do
      it { should_not be_running }
      it { should_not be_enabled }
      it { should_not be_installed }
    end
  end
end
