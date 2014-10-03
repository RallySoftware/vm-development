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

set :backend, :ssh

def wait_until(timeout=2)
  time_to_stop = Time.now + timeout
  while true
    rval = yield
    return rval if rval
    raise TimeoutError, "timeout of #{timeout}s exceeded" if Time.now > time_to_stop
    Thread.pass
  end
end

## returns the primary ip address associated to the given interface
def ip(interface='eth0')
  %Q{`ifconfig #{interface} | grep 'inet addr:' | cut -d: -f2 | cut -d' ' -f1`}
end

## validates that a password given on stdin hashes to match the value stored in /etc/shadow
def chkpasswd(username)
  %Q{openssl passwd -1 -stdin -salt `grep #{username} /etc/shadow | awk -F'$' '{print $3}'` | grep -q -F -f - /etc/shadow}
end


RSpec.configure do |c|
  c.formatter = :documentation
  c.color = true
  c.tty = true
  c.before :all do
    set :host, remote_host
    set :ssh_options, user: spec_user, password: spec_password
  end
end
