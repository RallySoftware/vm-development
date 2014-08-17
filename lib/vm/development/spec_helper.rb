require 'serverspec'
require 'pathname'
require 'net/ssh'

def remote_host_ssh(host, username, password)
  options  = Net::SSH::Config.for(host)
  user     = username
  options[:password] = password
  options[:paranoid] = false
  Net::SSH.start(host, user, options)
end

remote_host = ENV['REMOTE_HOST'].to_s.strip
raise 'REMOTE_HOST not set' if remote_host.empty?

spec_user = ENV['SPEC_USER'].to_s.strip
raise 'SPEC_USER not set' if spec_user.empty?

spec_password = ENV['SPEC_PASSWORD'].to_s.strip
raise 'SPEC_PASSWORD not set' if spec_password.empty?

puts "Running specs remotely on [#{spec_user}@#{remote_host}]"
remote_host_ssh(remote_host, spec_user, spec_password).close

include Serverspec::Helper::DetectOS
include Serverspec::Helper::Ssh

def wait_until(timeout=2)
  time_to_stop = Time.now + timeout
  while true
    rval = yield
    return rval if rval
    raise TimeoutError, "timeout of #{timeout}s exceeded" if Time.now > time_to_stop
    Thread.pass
  end
end

def ip(interface='eth0')
  %Q{`ifconfig #{interface} | grep 'inet addr:' | cut -d: -f2 | cut -d' ' -f1`}
end

RSpec.configure do |c|
  c.formatter = :documentation
  c.color = true
  c.tty = true
  c.before :all do
    if c.host != remote_host
      c.ssh.close if c.ssh
      c.host = remote_host
      c.ssh = remote_host_ssh c.host, spec_user, spec_password
    end
  end
end
